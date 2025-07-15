#!/bin/bash

# Comprehensive Debug and Test Script
# Identifies why SSH goes down during VM creation

set -e

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

LOG_FILE="/tmp/vm_debug_$(date +%Y%m%d_%H%M%S).log"

debug_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_log() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
}

warning_log() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

success_log() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" | tee -a "$LOG_FILE"
}

check_system_resources() {
    debug_log "=== SYSTEM RESOURCE CHECK ==="
    
    # Check total RAM
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    local used_ram_gb=$(free -g | awk '/^Mem:/{print $3}')
    
    debug_log "RAM Status:"
    debug_log "  Total RAM: ${total_ram_gb}GB"
    debug_log "  Used RAM: ${used_ram_gb}GB"
    debug_log "  Available RAM: ${available_ram_gb}GB"
    
    # Check if we have enough RAM for 10 VMs (20GB needed)
    if [ $available_ram_gb -lt 25 ]; then
        error_log "INSUFFICIENT RAM: Need 25GB+, have ${available_ram_gb}GB available"
        error_log "This will cause system instability and SSH crashes!"
        return 1
    else
        success_log "RAM check passed: ${available_ram_gb}GB available"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    debug_log "CPU Cores: $cpu_cores"
    
    if [ $cpu_cores -lt 4 ]; then
        warning_log "LOW CPU CORES: $cpu_cores cores for 10 VMs may cause performance issues"
    fi
    
    # Check disk space
    local disk_available_gb=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    debug_log "Disk Space Available: ${disk_available_gb}GB"
    
    if [ $disk_available_gb -lt 250 ]; then
        error_log "INSUFFICIENT DISK SPACE: Need 250GB+, have ${disk_available_gb}GB"
        return 1
    fi
    
    return 0
}

check_network_configuration() {
    debug_log "=== NETWORK CONFIGURATION CHECK ==="
    
    # Check current network interfaces
    debug_log "Network Interfaces:"
    ip addr show | grep -E "^[0-9]|inet " | tee -a "$LOG_FILE"
    
    # Check if bridge networking is set up
    if brctl show 2>/dev/null | grep -q virbr0; then
        debug_log "Libvirt bridge found: virbr0"
    else
        warning_log "No libvirt bridge found - this might cause networking issues"
    fi
    
    # Check for conflicting network ranges
    debug_log "Checking for network conflicts..."
    
    # QEMU uses 10.0.2.0/24 by default - check if this conflicts
    if ip route | grep -q "10.0.2."; then
        error_log "NETWORK CONFLICT: 10.0.2.0/24 is already in use!"
        error_log "This will cause VM networking issues and potentially SSH problems"
        return 1
    fi
    
    # Check SSH daemon status
    if systemctl is-active --quiet ssh; then
        debug_log "SSH service is running"
    else
        error_log "SSH service is not running!"
        return 1
    fi
    
    return 0
}

check_running_processes() {
    debug_log "=== RUNNING PROCESSES CHECK ==="
    
    # Check for existing QEMU processes
    local qemu_count=$(pgrep -f qemu-system-x86_64 | wc -l)
    debug_log "Existing QEMU processes: $qemu_count"
    
    if [ $qemu_count -gt 0 ]; then
        warning_log "Found $qemu_count existing QEMU processes"
        debug_log "Existing QEMU processes:"
        ps aux | grep qemu-system-x86_64 | grep -v grep | tee -a "$LOG_FILE"
    fi
    
    # Check for processes using high CPU/Memory
    debug_log "Top resource consumers:"
    ps aux --sort=-%cpu | head -10 | tee -a "$LOG_FILE"
    
    return 0
}

check_system_limits() {
    debug_log "=== SYSTEM LIMITS CHECK ==="
    
    # Check ulimits
    debug_log "File descriptor limits:"
    debug_log "  Soft limit: $(ulimit -n)"
    debug_log "  Hard limit: $(ulimit -Hn)"
    
    # Check process limits
    debug_log "Process limits:"
    debug_log "  Max user processes: $(ulimit -u)"
    
    # Check memory limits
    debug_log "Memory limits:"
    debug_log "  Virtual memory: $(ulimit -v)"
    
    # Check if we might hit limits with 10 VMs
    local max_processes=$(ulimit -u)
    if [ $max_processes -lt 1000 ]; then
        warning_log "LOW PROCESS LIMIT: $max_processes (may cause issues with multiple VMs)"
    fi
    
    return 0
}

test_single_vm_creation() {
    debug_log "=== SINGLE VM CREATION TEST ==="
    
    # Create a single VM to test resource usage
    debug_log "Creating single test VM..."
    
    # Clean up any existing test VMs
    pkill -f "test-vm" 2>/dev/null || true
    rm -f /tmp/test-vm.qcow2 2>/dev/null || true
    
    # Create a minimal test VM
    qemu-img create -f qcow2 /tmp/test-vm.qcow2 1G
    
    # Monitor system resources before starting VM
    debug_log "Resources before VM start:"
    free -h | tee -a "$LOG_FILE"
    
    # Start test VM
    debug_log "Starting test VM..."
    qemu-system-x86_64 \
        -enable-kvm \
        -m 1024M \
        -smp 1 \
        -drive file=/tmp/test-vm.qcow2,format=qcow2,if=virtio \
        -netdev user,id=net0 \
        -device virtio-net-pci,netdev=net0 \
        -vnc :99 \
        -display none \
        -daemonize \
        -pidfile /tmp/test-vm.pid \
        -no-reboot
    
    local vm_pid=$(cat /tmp/test-vm.pid)
    debug_log "Test VM started with PID: $vm_pid"
    
    # Monitor resources after VM start
    sleep 5
    debug_log "Resources after VM start:"
    free -h | tee -a "$LOG_FILE"
    
    # Check if SSH is still responsive
    if systemctl is-active --quiet ssh; then
        success_log "SSH still running after VM start"
    else
        error_log "SSH went down after starting single VM!"
        return 1
    fi
    
    # Clean up test VM
    kill $vm_pid 2>/dev/null || true
    rm -f /tmp/test-vm.qcow2 /tmp/test-vm.pid
    
    debug_log "Single VM test completed successfully"
    return 0
}

test_multiple_vm_creation() {
    debug_log "=== MULTIPLE VM CREATION TEST ==="
    
    local test_vm_count=3
    debug_log "Testing creation of $test_vm_count VMs..."
    
    # Clean up any existing test VMs
    pkill -f "multi-test-vm" 2>/dev/null || true
    rm -f /tmp/multi-test-vm-*.qcow2 2>/dev/null || true
    
    local vm_pids=()
    
    for i in $(seq 1 $test_vm_count); do
        debug_log "Creating test VM $i..."
        
        # Create disk
        qemu-img create -f qcow2 /tmp/multi-test-vm-${i}.qcow2 1G
        
        # Start VM
        qemu-system-x86_64 \
            -enable-kvm \
            -m 1024M \
            -smp 1 \
            -drive file=/tmp/multi-test-vm-${i}.qcow2,format=qcow2,if=virtio \
            -netdev user,id=net0 \
            -device virtio-net-pci,netdev=net0 \
            -vnc :$((99 + i)) \
            -display none \
            -daemonize \
            -pidfile /tmp/multi-test-vm-${i}.pid \
            -no-reboot
        
        local vm_pid=$(cat /tmp/multi-test-vm-${i}.pid)
        vm_pids+=($vm_pid)
        debug_log "Test VM $i started with PID: $vm_pid"
        
        # Monitor resources after each VM
        debug_log "Resources after VM $i:"
        free -h | tee -a "$LOG_FILE"
        
        # Check SSH status
        if ! systemctl is-active --quiet ssh; then
            error_log "SSH went down after starting VM $i!"
            
            # Clean up VMs
            for pid in "${vm_pids[@]}"; do
                kill $pid 2>/dev/null || true
            done
            
            return 1
        fi
        
        # Small delay between VM starts
        sleep 3
    done
    
    debug_log "All $test_vm_count VMs started successfully"
    debug_log "Final resource usage:"
    free -h | tee -a "$LOG_FILE"
    ps aux | grep qemu | grep -v grep | tee -a "$LOG_FILE"
    
    # Clean up test VMs
    for pid in "${vm_pids[@]}"; do
        kill $pid 2>/dev/null || true
    done
    
    for i in $(seq 1 $test_vm_count); do
        rm -f /tmp/multi-test-vm-${i}.qcow2 /tmp/multi-test-vm-${i}.pid
    done
    
    success_log "Multiple VM test completed successfully"
    return 0
}

check_ssh_configuration() {
    debug_log "=== SSH CONFIGURATION CHECK ==="
    
    # Check SSH config
    debug_log "SSH Configuration:"
    if [ -f /etc/ssh/sshd_config ]; then
        grep -E "^(Port|ListenAddress|MaxStartups|MaxSessions)" /etc/ssh/sshd_config | tee -a "$LOG_FILE"
    fi
    
    # Check SSH connections
    debug_log "Current SSH connections:"
    ss -tuln | grep :22 | tee -a "$LOG_FILE"
    
    # Check system load
    debug_log "System load:"
    uptime | tee -a "$LOG_FILE"
    
    return 0
}

recommend_solutions() {
    debug_log "=== RECOMMENDED SOLUTIONS ==="
    
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    
    if [ $available_ram_gb -lt 25 ]; then
        error_log "SOLUTION 1: REDUCE VM COUNT"
        debug_log "  Current RAM: ${available_ram_gb}GB available"
        debug_log "  Recommended VM count: $((available_ram_gb / 3))"
        debug_log "  Command: ./scale_vms.sh $((available_ram_gb / 3))"
        
        error_log "SOLUTION 2: REDUCE VM RAM"
        debug_log "  Edit scripts/generate_vm_configs.py"
        debug_log "  Change RAM from 2048MB to 1024MB"
        
        error_log "SOLUTION 3: STAGED CREATION"
        debug_log "  Create VMs in batches of 2-3"
        debug_log "  Wait between batches"
    fi
    
    warning_log "SOLUTION 4: NETWORK ISOLATION"
    debug_log "  Add network isolation to prevent conflicts"
    debug_log "  Use bridge networking instead of user networking"
    
    warning_log "SOLUTION 5: RESOURCE MONITORING"
    debug_log "  Monitor system resources during creation"
    debug_log "  Use: watch -n 2 free -h"
    debug_log "  Use: htop to monitor processes"
    
    warning_log "SOLUTION 6: SSH KEEPALIVE"
    debug_log "  Configure SSH client keepalive"
    debug_log "  Add to ~/.ssh/config:"
    debug_log "    ServerAliveInterval 30"
    debug_log "    ServerAliveCountMax 3"
}

create_safe_vm_script() {
    debug_log "=== CREATING SAFE VM CREATION SCRIPT ==="
    
    local safe_script="create_vms_safe.sh"
    
    cat > "$safe_script" << 'EOF'
#!/bin/bash

# Safe VM Creation Script - Prevents SSH crashes
# Creates VMs with resource monitoring and staged deployment

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_resources() {
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    local load_avg=$(uptime | awk '{print $10}' | cut -d',' -f1)
    
    log "Available RAM: ${available_ram_gb}GB"
    log "Load average: $load_avg"
    
    if [ $available_ram_gb -lt 5 ]; then
        log "ERROR: Not enough RAM available (${available_ram_gb}GB < 5GB)"
        return 1
    fi
    
    if (( $(echo "$load_avg > 5.0" | bc -l) )); then
        log "ERROR: System load too high ($load_avg)"
        return 1
    fi
    
    return 0
}

create_vm_batch() {
    local start_vm=$1
    local end_vm=$2
    local batch_size=$((end_vm - start_vm + 1))
    
    log "Creating VM batch: $start_vm to $end_vm ($batch_size VMs)"
    
    for i in $(seq $start_vm $end_vm); do
        log "Creating VM $i..."
        
        # Check resources before each VM
        if ! check_resources; then
            log "Stopping VM creation due to resource constraints"
            return 1
        fi
        
        # Create VM with reduced resources
        local vm_config_file="vm_configs/vm-${i}.json"
        if [ ! -f "$vm_config_file" ]; then
            log "Config file not found: $vm_config_file"
            continue
        fi
        
        # Extract VM info
        local vm_name=$(jq -r '.vm_name' "$vm_config_file")
        local ram_mb=1024  # Reduced from 2048MB
        local vnc_port_host=$(jq -r '.vnc_port_host' "$vm_config_file")
        
        # Create VM disk
        local disk_path="vm_disks/${vm_name}.qcow2"
        qemu-img create -f qcow2 "$disk_path" 20G
        
        # Start VM with reduced resources
        qemu-system-x86_64 \
            -enable-kvm \
            -m ${ram_mb}M \
            -smp 1 \
            -drive file="$disk_path",format=qcow2,if=virtio \
            -netdev user,id=net0,hostfwd=tcp::$vnc_port_host-:5900 \
            -device virtio-net-pci,netdev=net0 \
            -vnc :$((vnc_port_host - 5900)) \
            -display none \
            -daemonize \
            -pidfile "/var/run/${vm_name}.pid" &
        
        log "VM $i started (PID: $!)"
        
        # Wait and monitor
        sleep 10
        
        # Check if SSH is still responsive
        if ! systemctl is-active --quiet ssh; then
            log "ERROR: SSH went down after VM $i!"
            return 1
        fi
        
        log "VM $i: SSH still responsive"
    done
    
    log "Batch $start_vm-$end_vm completed successfully"
    return 0
}

main() {
    log "Starting safe VM creation..."
    
    # Generate configs
    python3 scripts/generate_vm_configs.py
    
    # Create VMs in batches of 2
    local total_vms=10
    local batch_size=2
    
    for start_vm in $(seq 1 $batch_size $total_vms); do
        local end_vm=$((start_vm + batch_size - 1))
        if [ $end_vm -gt $total_vms ]; then
            end_vm=$total_vms
        fi
        
        log "=== Starting batch: VMs $start_vm to $end_vm ==="
        
        if ! create_vm_batch $start_vm $end_vm; then
            log "ERROR: Batch creation failed!"
            exit 1
        fi
        
        # Wait between batches
        if [ $end_vm -lt $total_vms ]; then
            log "Waiting 30 seconds before next batch..."
            sleep 30
        fi
    done
    
    log "All VMs created successfully!"
    log "Total VMs: $(pgrep -f qemu-system-x86_64 | wc -l)"
}

main "$@"
EOF

    chmod +x "$safe_script"
    success_log "Created safe VM creation script: $safe_script"
}

main() {
    debug_log "Starting comprehensive VM system debugging..."
    debug_log "Log file: $LOG_FILE"
    
    local overall_status=0
    
    # Run all checks
    if ! check_system_resources; then
        overall_status=1
    fi
    
    if ! check_network_configuration; then
        overall_status=1
    fi
    
    check_running_processes
    check_system_limits
    check_ssh_configuration
    
    # Run tests if basic checks pass
    if [ $overall_status -eq 0 ]; then
        if ! test_single_vm_creation; then
            overall_status=1
        fi
        
        if [ $overall_status -eq 0 ]; then
            if ! test_multiple_vm_creation; then
                overall_status=1
            fi
        fi
    fi
    
    # Provide solutions
    recommend_solutions
    create_safe_vm_script
    
    debug_log "=== DEBUGGING COMPLETE ==="
    debug_log "Log file saved to: $LOG_FILE"
    
    if [ $overall_status -eq 0 ]; then
        success_log "All tests passed! System should be stable for VM creation."
    else
        error_log "Issues found! Please address the problems above before creating VMs."
    fi
    
    return $overall_status
}

# Run main function
main "$@"