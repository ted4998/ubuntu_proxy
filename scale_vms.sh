#!/bin/bash

# VM Manager Scaling Helper
# Easily scale between 10 and 20 VMs

set -e

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

show_usage() {
    echo "Usage: $0 [10|20|status]"
    echo ""
    echo "Commands:"
    echo "  10     - Scale to 10 VMs"
    echo "  20     - Scale to 20 VMs" 
    echo "  status - Show current configuration"
    echo ""
    echo "Examples:"
    echo "  $0 10     # Configure for 10 VMs"
    echo "  $0 20     # Configure for 20 VMs"
    echo "  $0 status # Show current VM count"
}

show_status() {
    echo "=== Current VM Configuration ==="
    
    # Check main script
    if [ -f "manage_vms.sh" ]; then
        current_vms=$(grep "NUM_VMS=" manage_vms.sh | head -1 | cut -d'=' -f2)
        echo "Current VM count: $current_vms"
    else
        echo "manage_vms.sh not found"
        return 1
    fi
    
    # Check consistency
    echo ""
    echo "Configuration consistency check:"
    
    files_to_check=("manage_vms.sh" "scripts/generate_vm_configs.py" "validate_system.sh" "cleanup_vm_environment.sh")
    
    for file in "${files_to_check[@]}"; do
        if [ -f "$file" ]; then
            if [ "$file" = "scripts/generate_vm_configs.py" ]; then
                vm_count=$(grep "NUM_VMS = " "$file" | head -1 | awk '{print $3}')
            else
                vm_count=$(grep "NUM_VMS=" "$file" | head -1 | cut -d'=' -f2)
            fi
            echo "  $file: $vm_count VMs"
        else
            echo "  $file: NOT FOUND"
        fi
    done
    
    echo ""
    echo "Resource requirements for $current_vms VMs:"
    echo "  Disk space: $((current_vms * 20))GB + overhead"
    echo "  RAM: $((current_vms * 2))GB + host overhead"
    echo "  VNC ports: 5900-$((5899 + current_vms))"
    echo "  HTTP ports: 8000-$((7999 + current_vms))"
}

scale_to_vms() {
    local target_vms=$1
    
    echo "=== Scaling to $target_vms VMs ==="
    
    # Validate target
    if [ "$target_vms" != "10" ] && [ "$target_vms" != "20" ]; then
        echo "Error: Only 10 or 20 VMs are supported"
        return 1
    fi
    
    # Check if any VMs are running
    if ps aux | grep -q "qemu-system-x86_64.*ubuntu-vm-"; then
        echo "WARNING: VMs are currently running!"
        echo "Please run 'sudo ./complete_cleanup.sh' first to stop all VMs."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting."
            return 1
        fi
    fi
    
    echo "Updating configuration files..."
    
    # Update main script
    if [ -f "manage_vms.sh" ]; then
        sed -i "s/NUM_VMS=[0-9]*/NUM_VMS=$target_vms/g" manage_vms.sh
        echo "  ✓ Updated manage_vms.sh"
    fi
    
    # Update Python script
    if [ -f "scripts/generate_vm_configs.py" ]; then
        sed -i "s/NUM_VMS = [0-9]*/NUM_VMS = $target_vms/g" scripts/generate_vm_configs.py
        echo "  ✓ Updated scripts/generate_vm_configs.py"
    fi
    
    # Update validation script
    if [ -f "validate_system.sh" ]; then
        sed -i "s/NUM_VMS=[0-9]*/NUM_VMS=$target_vms/g" validate_system.sh
        echo "  ✓ Updated validate_system.sh"
    fi
    
    # Update cleanup script
    if [ -f "cleanup_vm_environment.sh" ]; then
        sed -i "s/NUM_VMS=[0-9]*/NUM_VMS=$target_vms/g" cleanup_vm_environment.sh
        echo "  ✓ Updated cleanup_vm_environment.sh"
    fi
    
    # Update port ranges in monitoring scripts
    if [ "$target_vms" = "20" ]; then
        # Update to 20 VM port ranges
        sed -i 's/8000-8009/8000-8019/g' complete_cleanup.sh 2>/dev/null || true
        sed -i 's/{5900..5909}/{5900..5919}/g' monitor_progress.sh check_status.sh 2>/dev/null || true
        sed -i 's/{8000..8009}/{8000..8019}/g' check_status.sh 2>/dev/null || true
        echo "  ✓ Updated port ranges for 20 VMs"
    else
        # Update to 10 VM port ranges  
        sed -i 's/8000-8019/8000-8009/g' complete_cleanup.sh 2>/dev/null || true
        sed -i 's/{5900..5919}/{5900..5909}/g' monitor_progress.sh check_status.sh 2>/dev/null || true
        sed -i 's/{8000..8019}/{8000..8009}/g' check_status.sh 2>/dev/null || true
        echo "  ✓ Updated port ranges for 10 VMs"
    fi
    
    echo ""
    echo "=== Configuration Updated Successfully ==="
    echo "VM count: $target_vms"
    echo ""
    echo "Next steps:"
    echo "1. Clean up any existing VMs: sudo ./complete_cleanup.sh"
    echo "2. Validate system: ./validate_system.sh"
    if [ "$target_vms" = "20" ]; then
        echo "3. Start VMs: sudo ./start_20_vms.sh"
    else
        echo "3. Start VMs: sudo ./start_10_vms.sh"
    fi
    echo "4. Monitor progress: ./monitor_progress.sh"
}

# Main script logic
case "${1:-}" in
    "10")
        scale_to_vms 10
        ;;
    "20")
        scale_to_vms 20
        ;;
    "status")
        show_status
        ;;
    "help"|"--help"|"-h")
        show_usage
        ;;
    "")
        show_usage
        exit 1
        ;;
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_usage
        exit 1
        ;;
esac