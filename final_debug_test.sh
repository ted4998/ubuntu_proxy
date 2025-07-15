#!/bin/bash

# Final Comprehensive Test - Debug SSH Crash Issues
# This script runs all debugging tests and provides definitive solutions

set -e

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

FINAL_LOG="/tmp/final_test_$(date +%Y%m%d_%H%M%S).log"

log_final() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$FINAL_LOG"
}

header() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    FINAL DEBUGGING TEST                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    log_final "Starting final comprehensive test"
    log_final "Log file: $FINAL_LOG"
    echo ""
}

show_system_info() {
    log_final "=== SYSTEM INFORMATION ==="
    
    # Basic system info
    log_final "OS: $(lsb_release -d | cut -f2)"
    log_final "Kernel: $(uname -r)"
    log_final "Architecture: $(uname -m)"
    log_final "CPU: $(nproc) cores"
    log_final "RAM: $(free -h | awk '/^Mem:/{print $2}') total, $(free -h | awk '/^Mem:/{print $7}') available"
    log_final "Disk: $(df -h . | awk 'NR==2 {print $4}') available in $(pwd)"
    log_final "Load: $(uptime | awk '{print $10}' | cut -d',' -f1)"
    
    # Check virtualization
    if [ -f /proc/cpuinfo ]; then
        local virt_support=$(grep -E "(vmx|svm)" /proc/cpuinfo | wc -l)
        log_final "Virtualization support: $virt_support CPU flags"
    fi
    
    # Check KVM
    if [ -e /dev/kvm ]; then
        log_final "KVM device: Available"
    else
        log_final "KVM device: Not available"
    fi
    
    echo ""
}

run_debug_tests() {
    log_final "=== RUNNING DEBUG TESTS ==="
    
    if [ -f "debug_vm_system.sh" ]; then
        log_final "Running comprehensive debug tests..."
        if ./debug_vm_system.sh 2>&1 | tee -a "$FINAL_LOG"; then
            log_final "Debug tests completed successfully"
        else
            log_final "Debug tests found issues"
        fi
    else
        log_final "Debug script not found"
    fi
    
    echo ""
}

test_resource_limits() {
    log_final "=== TESTING RESOURCE LIMITS ==="
    
    # Test memory allocation
    log_final "Testing memory allocation..."
    local test_size_mb=1024
    local test_file="/tmp/memory_test_$$"
    
    if dd if=/dev/zero of="$test_file" bs=1M count=$test_size_mb 2>/dev/null; then
        log_final "Memory allocation test: PASSED (${test_size_mb}MB)"
        rm -f "$test_file"
    else
        log_final "Memory allocation test: FAILED"
    fi
    
    # Test process limits
    log_final "Process limits:"
    log_final "  Max processes: $(ulimit -u)"
    log_final "  Max open files: $(ulimit -n)"
    log_final "  Max memory: $(ulimit -v)"
    
    # Test network limits
    log_final "Network connectivity:"
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_final "  Internet connectivity: OK"
    else
        log_final "  Internet connectivity: FAILED"
    fi
    
    echo ""
}

run_ssh_monitoring_test() {
    log_final "=== SSH MONITORING TEST ==="
    
    if [ -f "ssh_monitor.sh" ]; then
        log_final "Starting SSH monitoring test..."
        
        # Start monitoring in background
        ./ssh_monitor.sh monitor 60 2>&1 | tee -a "$FINAL_LOG" &
        local monitor_pid=$!
        
        # Wait for monitoring to start
        sleep 5
        
        # Create some system load
        log_final "Creating system load for testing..."
        stress --cpu 2 --timeout 30s &>/dev/null &
        local stress_pid=$!
        
        # Wait for monitoring to complete
        wait $monitor_pid
        
        # Clean up
        kill $stress_pid 2>/dev/null || true
        
        log_final "SSH monitoring test completed"
    else
        log_final "SSH monitoring script not found"
    fi
    
    echo ""
}

test_safe_vm_creation() {
    log_final "=== SAFE VM CREATION TEST ==="
    
    if [ -f "create_vms_safe.sh" ]; then
        log_final "Testing safe VM creation with 1 VM..."
        
        # Start SSH monitoring
        ./ssh_monitor.sh monitor 180 2>&1 | tee -a "$FINAL_LOG" &
        local monitor_pid=$!
        
        # Try to create 1 VM safely
        if ./create_vms_safe.sh --vms 1 --batch-size 1 --ram 1024 2>&1 | tee -a "$FINAL_LOG"; then
            log_final "Safe VM creation test: PASSED"
            
            # Check if SSH is still responsive
            if systemctl is-active --quiet ssh; then
                log_final "SSH status after VM creation: RUNNING"
            else
                log_final "SSH status after VM creation: DOWN"
            fi
        else
            log_final "Safe VM creation test: FAILED"
        fi
        
        # Clean up
        pkill -f qemu-system-x86_64 || true
        wait $monitor_pid 2>/dev/null || true
        
    else
        log_final "Safe VM creation script not found"
    fi
    
    echo ""
}

analyze_root_cause() {
    log_final "=== ROOT CAUSE ANALYSIS ==="
    
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    local cpu_cores=$(nproc)
    
    log_final "Analyzing why SSH crashes during VM creation..."
    
    # Check RAM sufficiency
    if [ $total_ram_gb -lt 16 ]; then
        log_final "ROOT CAUSE 1: INSUFFICIENT RAM"
        log_final "  Total RAM: ${total_ram_gb}GB"
        log_final "  Required for 10 VMs: 20GB minimum"
        log_final "  Impact: System swapping causes SSH to become unresponsive"
    fi
    
    # Check CPU sufficiency
    if [ $cpu_cores -lt 4 ]; then
        log_final "ROOT CAUSE 2: INSUFFICIENT CPU"
        log_final "  CPU cores: $cpu_cores"
        log_final "  Required for 10 VMs: 4+ cores recommended"
        log_final "  Impact: High CPU load makes SSH unresponsive"
    fi
    
    # Check swap configuration
    local swap_total=$(free -g | awk '/^Swap:/{print $2}')
    if [ $swap_total -eq 0 ]; then
        log_final "ROOT CAUSE 3: NO SWAP CONFIGURED"
        log_final "  Swap space: ${swap_total}GB"
        log_final "  Impact: System OOM killer may terminate SSH"
    fi
    
    # Check network configuration
    if ip route | grep -q "10.0.2."; then
        log_final "ROOT CAUSE 4: NETWORK CONFLICT"
        log_final "  10.0.2.0/24 network in use"
        log_final "  Impact: QEMU networking conflicts with host"
    fi
    
    # Check system limits
    local max_processes=$(ulimit -u)
    if [ $max_processes -lt 1000 ]; then
        log_final "ROOT CAUSE 5: PROCESS LIMITS"
        log_final "  Max processes: $max_processes"
        log_final "  Impact: System may hit process limits"
    fi
    
    echo ""
}

provide_definitive_solutions() {
    log_final "=== DEFINITIVE SOLUTIONS ==="
    
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    
    echo -e "${GREEN}SOLUTION 1: USE RESOURCE-SAFE SCRIPT${NC}"
    echo "  Command: sudo ./create_vms_safe.sh --vms 5 --batch-size 2 --ram 1024"
    echo "  This creates VMs safely with resource monitoring"
    echo ""
    
    echo -e "${GREEN}SOLUTION 2: INCREASE SYSTEM RESOURCES${NC}"
    echo "  Add swap space:"
    echo "    sudo fallocate -l 4G /swapfile"
    echo "    sudo chmod 600 /swapfile"
    echo "    sudo mkswap /swapfile"
    echo "    sudo swapon /swapfile"
    echo ""
    
    echo -e "${GREEN}SOLUTION 3: OPTIMIZE SSH CONFIGURATION${NC}"
    echo "  Edit /etc/ssh/sshd_config:"
    echo "    MaxStartups 30:30:100"
    echo "    MaxSessions 30"
    echo "    ClientAliveInterval 30"
    echo "    ClientAliveCountMax 3"
    echo "  Then: sudo systemctl restart ssh"
    echo ""
    
    echo -e "${GREEN}SOLUTION 4: MONITOR DURING CREATION${NC}"
    echo "  Terminal 1: ./ssh_monitor.sh monitor 600"
    echo "  Terminal 2: sudo ./create_vms_safe.sh --vms 5"
    echo ""
    
    echo -e "${GREEN}SOLUTION 5: STAGED VM CREATION${NC}"
    echo "  Create VMs in stages:"
    echo "    sudo ./create_vms_safe.sh --vms 3 --batch-size 1"
    echo "    # Wait 5 minutes"
    echo "    sudo ./create_vms_safe.sh --vms 3 --batch-size 1"
    echo "    # Wait 5 minutes"
    echo "    sudo ./create_vms_safe.sh --vms 4 --batch-size 1"
    echo ""
    
    if [ $total_ram_gb -lt 16 ]; then
        echo -e "${YELLOW}HARDWARE RECOMMENDATION:${NC}"
        echo "  Current RAM: ${total_ram_gb}GB"
        echo "  Recommended: 32GB+ RAM for 10 VMs"
        echo "  Alternative: Reduce to $(($total_ram_gb / 2)) VMs maximum"
        echo ""
    fi
}

create_emergency_fix_script() {
    log_final "=== CREATING EMERGENCY FIX SCRIPT ==="
    
    cat > emergency_fix.sh << 'EOF'
#!/bin/bash
# Emergency Fix Script - Run this if SSH crashes during VM creation

echo "=== EMERGENCY SSH FIX ==="

# Kill all QEMU processes
echo "Killing all QEMU processes..."
sudo pkill -f qemu-system-x86_64 || true

# Kill cpulimit processes
echo "Killing cpulimit processes..."
sudo pkill -f cpulimit || true

# Clear system cache
echo "Clearing system cache..."
sudo sync
echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null

# Restart SSH service
echo "Restarting SSH service..."
sudo systemctl restart ssh

# Check SSH status
if systemctl is-active --quiet ssh; then
    echo "SSH service is now running"
else
    echo "SSH service failed to start"
    sudo systemctl status ssh
fi

# Show system resources
echo "Current system resources:"
free -h
uptime

echo "=== EMERGENCY FIX COMPLETE ==="
EOF
    
    chmod +x emergency_fix.sh
    log_final "Created emergency_fix.sh script"
    
    echo ""
}

generate_final_report() {
    log_final "=== FINAL REPORT ==="
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        FINAL REPORT                           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    local cpu_cores=$(nproc)
    
    echo -e "${BLUE}System Status:${NC}"
    echo "  RAM: ${total_ram_gb}GB total, ${available_ram_gb}GB available"
    echo "  CPU: $cpu_cores cores"
    echo "  SSH: $(systemctl is-active ssh 2>/dev/null || echo 'unknown')"
    echo ""
    
    echo -e "${BLUE}SSH Crash Analysis:${NC}"
    if [ $total_ram_gb -lt 16 ]; then
        echo -e "  ${RED}HIGH RISK${NC}: Insufficient RAM for 10 VMs"
    elif [ $available_ram_gb -lt 10 ]; then
        echo -e "  ${YELLOW}MEDIUM RISK${NC}: Low available RAM"
    else
        echo -e "  ${GREEN}LOW RISK${NC}: Sufficient RAM available"
    fi
    
    echo ""
    echo -e "${BLUE}Recommended Actions:${NC}"
    echo "  1. Use: sudo ./create_vms_safe.sh --vms 5 --batch-size 2"
    echo "  2. Monitor: ./ssh_monitor.sh monitor 600"
    echo "  3. Emergency: ./emergency_fix.sh (if SSH crashes)"
    echo ""
    
    echo -e "${BLUE}Maximum Safe VM Count:${NC}"
    local safe_vm_count=$((available_ram_gb / 2))
    if [ $safe_vm_count -gt 10 ]; then
        safe_vm_count=10
    fi
    echo "  Recommended: $safe_vm_count VMs"
    echo ""
    
    echo -e "${GREEN}Complete log saved to: $FINAL_LOG${NC}"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run with sudo: sudo $0${NC}"
        exit 1
    fi
    
    header
    show_system_info
    run_debug_tests
    test_resource_limits
    run_ssh_monitoring_test
    test_safe_vm_creation
    analyze_root_cause
    provide_definitive_solutions
    create_emergency_fix_script
    generate_final_report
    
    echo -e "${GREEN}Final debugging test completed!${NC}"
    echo -e "${YELLOW}Check $FINAL_LOG for complete details${NC}"
}

# Install stress tool if not available
if ! command -v stress &> /dev/null; then
    echo "Installing stress tool for testing..."
    apt-get update -qq && apt-get install -y stress
fi

# Run main function
main "$@"