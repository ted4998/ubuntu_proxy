#!/bin/bash

# Resource-Safe VM Creation Script
# Prevents SSH crashes by monitoring system resources

set -e

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

# Configuration
MAX_CONCURRENT_VMS=3
VM_RAM_MB=1024  # Reduced from 2048MB
BATCH_DELAY=30
RESOURCE_CHECK_INTERVAL=10

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error_log() {
    echo -e "${RED}[ERROR] $1${NC}"
}

success_log() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning_log() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

check_system_resources() {
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    local load_avg=$(uptime | awk '{print $10}' | cut -d',' -f1)
    local cpu_count=$(nproc)
    
    # Check RAM
    if [ $available_ram_gb -lt 3 ]; then
        error_log "Insufficient RAM: ${available_ram_gb}GB available (need 3GB minimum)"
        return 1
    fi
    
    # Check CPU load
    if (( $(echo "$load_avg > $((cpu_count * 2))" | bc -l 2>/dev/null || echo "0") )); then
        error_log "High CPU load: $load_avg (CPU cores: $cpu_count)"
        return 1
    fi
    
    # Check SSH service
    if ! systemctl is-active --quiet ssh; then
        error_log "SSH service is not running!"
        return 1
    fi
    
    log "Resources OK - RAM: ${available_ram_gb}GB, Load: $load_avg, CPUs: $cpu_count"
    return 0
}

wait_for_resources() {
    local max_wait=300  # 5 minutes
    local waited=0
    
    while ! check_system_resources && [ $waited -lt $max_wait ]; do
        warning_log "Waiting for resources to stabilize..."
        sleep 10
        waited=$((waited + 10))
    done
    
    if [ $waited -ge $max_wait ]; then
        error_log "Timeout waiting for resources"
        return 1
    fi
    
    return 0
}

create_vm_safely() {
    local vm_id=$1
    local vm_config_file="vm_configs/vm-${vm_id}.json"
    
    if [ ! -f "$vm_config_file" ]; then
        error_log "Config file not found: $vm_config_file"
        return 1
    fi
    
    # Extract VM configuration
    local vm_name=$(jq -r '.vm_name' "$vm_config_file")
    local mac_address=$(jq -r '.mac_address' "$vm_config_file")
    local vnc_port_host=$(jq -r '.vnc_port_host' "$vm_config_file")
    local vm_uuid=$(jq -r '.uuid' "$vm_config_file")
    local bios_serial=$(jq -r '.bios_serial' "$vm_config_file")
    local cpu_model=$(jq -r '.cpu_model' "$vm_config_file")
    
    local disk_image_path="vm_disks/${vm_name}.qcow2"
    
    log "Creating VM: $vm_name"
    
    # Check resources before creating VM
    if ! check_system_resources; then
        error_log "Cannot create VM $vm_name - insufficient resources"
        return 1
    fi
    
    # Create disk image
    mkdir -p vm_disks
    if [ ! -f "$disk_image_path" ]; then
        log "Creating disk image: $disk_image_path"
        qemu-img create -f qcow2 "$disk_image_path" 20G
    fi
    
    # Start VM with resource constraints
    log "Starting VM: $vm_name (RAM: ${VM_RAM_MB}MB, VNC: $vnc_port_host)"
    
    qemu-system-x86_64 \
        -enable-kvm \
        -m ${VM_RAM_MB}M \
        -smp 1 \
        -cpu "$cpu_model" \
        -uuid "$vm_uuid" \
        -smbios type=1,serial="$bios_serial" \
        -drive file="$disk_image_path",format=qcow2,if=virtio \
        -netdev user,id=net0,hostfwd=tcp::"$vnc_port_host"-:5900 \
        -device virtio-net-pci,netdev=net0,mac="$mac_address" \
        -vnc :"$((vnc_port_host - 5900))" \
        -k en-us \
        -machine q35,accel=kvm \
        -serial mon:stdio \
        -display none \
        -daemonize \
        -pidfile "/var/run/${vm_name}.pid" 2>/dev/null || {
        error_log "Failed to start VM: $vm_name"
        return 1
    }
    
    local vm_pid=$(cat "/var/run/${vm_name}.pid" 2>/dev/null)
    
    # Apply CPU limiting
    if [ -n "$vm_pid" ]; then
        cpulimit -p "$vm_pid" -l 80 > /dev/null 2>&1 &
        success_log "VM $vm_name started (PID: $vm_pid) with CPU limit"
    else
        warning_log "Could not get PID for VM $vm_name"
    fi
    
    # Monitor for a few seconds
    sleep 5
    
    # Verify VM is still running and SSH is responsive
    if ! systemctl is-active --quiet ssh; then
        error_log "SSH went down after starting VM $vm_name!"
        
        # Kill the VM
        if [ -n "$vm_pid" ]; then
            kill "$vm_pid" 2>/dev/null || true
        fi
        
        return 1
    fi
    
    success_log "VM $vm_name created successfully"
    return 0
}

create_vms_in_batches() {
    local total_vms=${1:-10}
    local batch_size=${2:-$MAX_CONCURRENT_VMS}
    
    log "Creating $total_vms VMs in batches of $batch_size"
    
    # Generate VM configurations
    log "Generating VM configurations..."
    python3 scripts/generate_vm_configs.py
    
    # Create output directory and info file
    mkdir -p output
    echo "# VM Information (Generated on $(date))" > output/vm_info.txt
    echo "# VM_Name,MAC_Address,VNC_Port_Host,VNC_Password,UUID,BIOS_Serial" >> output/vm_info.txt
    
    local created_vms=0
    
    for start_vm in $(seq 1 $batch_size $total_vms); do
        local end_vm=$((start_vm + batch_size - 1))
        if [ $end_vm -gt $total_vms ]; then
            end_vm=$total_vms
        fi
        
        log "=== Creating batch: VMs $start_vm to $end_vm ==="
        
        # Wait for resources to be available
        if ! wait_for_resources; then
            error_log "Cannot proceed - insufficient resources"
            break
        fi
        
        # Create VMs in current batch
        for vm_id in $(seq $start_vm $end_vm); do
            if create_vm_safely "$vm_id"; then
                created_vms=$((created_vms + 1))
                
                # Add to VM info file
                local vm_config_file="vm_configs/vm-${vm_id}.json"
                if [ -f "$vm_config_file" ]; then
                    local vm_name=$(jq -r '.vm_name' "$vm_config_file")
                    local mac_address=$(jq -r '.mac_address' "$vm_config_file")
                    local vnc_port_host=$(jq -r '.vnc_port_host' "$vm_config_file")
                    local vnc_password=$(jq -r '.vnc_password' "$vm_config_file")
                    local vm_uuid=$(jq -r '.uuid' "$vm_config_file")
                    local bios_serial=$(jq -r '.bios_serial' "$vm_config_file")
                    
                    echo "${vm_name},${mac_address},${vnc_port_host},${vnc_password},${vm_uuid},${bios_serial}" >> output/vm_info.txt
                fi
            else
                warning_log "Failed to create VM $vm_id - continuing with next batch"
                break
            fi
            
            # Small delay between VMs in same batch
            sleep 5
        done
        
        # Wait between batches
        if [ $end_vm -lt $total_vms ]; then
            log "Waiting ${BATCH_DELAY}s before next batch..."
            sleep $BATCH_DELAY
        fi
    done
    
    log "VM creation completed: $created_vms out of $total_vms VMs created"
    return 0
}

show_vm_status() {
    log "=== VM Status ==="
    
    local running_vms=$(pgrep -f qemu-system-x86_64 | wc -l)
    log "Running VMs: $running_vms"
    
    if [ $running_vms -gt 0 ]; then
        log "VM Details:"
        ps aux | grep qemu-system-x86_64 | grep -v grep | while read line; do
            echo "  $line"
        done
    fi
    
    log "VNC Ports:"
    for port in {5900..5909}; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            log "  Port $port: In use"
        fi
    done
    
    log "System Resources:"
    free -h
    uptime
}

main() {
    log "=== Resource-Safe VM Creation ==="
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error_log "Please run with sudo: sudo $0"
        exit 1
    fi
    
    # Parse command line arguments
    local vm_count=10
    local batch_size=$MAX_CONCURRENT_VMS
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vms)
                vm_count="$2"
                shift 2
                ;;
            --batch-size)
                batch_size="$2"
                shift 2
                ;;
            --ram)
                VM_RAM_MB="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --vms NUMBER       Number of VMs to create (default: 10)"
                echo "  --batch-size NUMBER VMs per batch (default: 3)"
                echo "  --ram MB           RAM per VM in MB (default: 1024)"
                echo "  --help             Show this help"
                exit 0
                ;;
            *)
                error_log "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    log "Configuration:"
    log "  VMs to create: $vm_count"
    log "  Batch size: $batch_size"
    log "  RAM per VM: ${VM_RAM_MB}MB"
    
    # Initial resource check
    if ! check_system_resources; then
        error_log "System does not meet minimum requirements"
        exit 1
    fi
    
    # Create VMs
    create_vms_in_batches "$vm_count" "$batch_size"
    
    # Show final status
    show_vm_status
    
    success_log "VM creation process completed"
    log "Check output/vm_info.txt for VNC connection details"
}

# Run main function
main "$@"