#!/bin/bash

# Alternative VM Creation Script - Manual Installation Method
# This script creates VMs but requires manual Ubuntu installation

set -e

PROJECT_DIR_REALPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR_REALPATH"

# Constants
NUM_VMS=10
VM_CONFIGS_DIR="${PROJECT_DIR_REALPATH}/vm_configs"
VM_DISKS_DIR="${PROJECT_DIR_REALPATH}/vm_disks"
ISO_DIR="${PROJECT_DIR_REALPATH}/iso"
ISO_FULL_PATH="${ISO_DIR}/ubuntu-desktop.iso"
OUTPUT_DIR="${PROJECT_DIR_REALPATH}/output"
VM_INFO_FILE="${OUTPUT_DIR}/vm_info.txt"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [PID:$$] $1"
}

# Create directories
mkdir -p "$VM_DISKS_DIR" "$OUTPUT_DIR"

# Generate VM info header
mkdir -p "$(dirname "$VM_INFO_FILE")"
echo "# VM Information (Generated on $(date))" > "$VM_INFO_FILE"
echo "# VM_Name,MAC_Address,VNC_Port_Host,VNC_Password,UUID,BIOS_Serial" >> "$VM_INFO_FILE"

log "=== Manual VM Creation Mode ==="
log "This will create $NUM_VMS VMs ready for manual Ubuntu installation"

# Generate VM configurations
log "Generating VM configurations..."
python3 scripts/generate_vm_configs.py

# Create VMs
for i in $(seq 1 "$NUM_VMS"); do
    local vm_config_file="${VM_CONFIGS_DIR}/vm-${i}.json"
    
    if [ ! -f "$vm_config_file" ]; then
        log "Error: VM config file $vm_config_file not found. Skipping VM $i."
        continue
    fi
    
    log "--- Creating VM $i ---"
    
    local vm_name=$(jq -r '.vm_name' "$vm_config_file")
    local mac_address=$(jq -r '.mac_address' "$vm_config_file")
    local vnc_port_host=$(jq -r '.vnc_port_host' "$vm_config_file")
    local vnc_password=$(jq -r '.vnc_password' "$vm_config_file")
    local vm_uuid=$(jq -r '.uuid' "$vm_config_file")
    local bios_serial=$(jq -r '.bios_serial' "$vm_config_file")
    local cpu_model=$(jq -r '.cpu_model' "$vm_config_file")
    local ram_mb=$(jq -r '.ram_size_mb' "$vm_config_file")
    local disk_size_gb=$(jq -r '.disk_size_gb' "$vm_config_file")
    
    local disk_image_path="${VM_DISKS_DIR}/${vm_name}.qcow2"
    
    # Create disk image
    log "Creating disk image (${disk_size_gb} GB) at $disk_image_path..."
    qemu-img create -f qcow2 "$disk_image_path" "${disk_size_gb}G"
    
    # Add VM info to file
    echo "${vm_name},${mac_address},${vnc_port_host},${vnc_password},${vm_uuid},${bios_serial}" >> "$VM_INFO_FILE"
    
    # Create VM startup script
    local vm_script="${PROJECT_DIR_REALPATH}/start_${vm_name}.sh"
    cat > "$vm_script" << EOF
#!/bin/bash

# Startup script for $vm_name
# VNC Access: localhost:$vnc_port_host (Display :$((vnc_port_host - 5900)))
# VNC Password: $vnc_password

echo "Starting $vm_name..."
echo "VNC Access: localhost:$vnc_port_host"
echo "VNC Password: $vnc_password"

# Installation mode (with ISO)
if [ "\$1" = "install" ]; then
    echo "Starting $vm_name in installation mode..."
    qemu-system-x86_64 \\
        -enable-kvm \\
        -m ${ram_mb}M \\
        -smp 1 \\
        -cpu "$cpu_model" \\
        -uuid "$vm_uuid" \\
        -smbios type=1,serial="$bios_serial" \\
        -drive file="$disk_image_path",format=qcow2,if=virtio \\
        -cdrom "$ISO_FULL_PATH" \\
        -boot d \\
        -netdev user,id=net0,hostfwd=tcp::$vnc_port_host-:5900 \\
        -device virtio-net-pci,netdev=net0,mac="$mac_address" \\
        -vnc :$((vnc_port_host - 5900)) \\
        -k en-us \\
        -machine q35,accel=kvm \\
        -serial mon:stdio \\
        -display none &
        
    VM_PID=\$!
    echo "VM PID: \$VM_PID"
    echo \$VM_PID > /var/run/${vm_name}.pid
    echo "$vm_name started in installation mode (PID: \$VM_PID)"
    
# Normal boot mode (after installation)
else
    echo "Starting $vm_name in normal mode..."
    qemu-system-x86_64 \\
        -enable-kvm \\
        -m ${ram_mb}M \\
        -smp 1 \\
        -cpu "$cpu_model" \\
        -uuid "$vm_uuid" \\
        -smbios type=1,serial="$bios_serial" \\
        -drive file="$disk_image_path",format=qcow2,if=virtio \\
        -boot c \\
        -netdev user,id=net0,hostfwd=tcp::$vnc_port_host-:5900 \\
        -device virtio-net-pci,netdev=net0,mac="$mac_address" \\
        -vnc :$((vnc_port_host - 5900)) \\
        -k en-us \\
        -machine q35,accel=kvm \\
        -serial mon:stdio \\
        -display none &
        
    VM_PID=\$!
    echo "VM PID: \$VM_PID"
    echo \$VM_PID > /var/run/${vm_name}.pid
    echo "$vm_name started in normal mode (PID: \$VM_PID)"
fi

echo "Connect via VNC: localhost:$vnc_port_host"
echo "Use password: $vnc_password"
EOF

    chmod +x "$vm_script"
    log "Created startup script: $vm_script"
    
    log "VM $vm_name prepared successfully"
done

log "=== VM Creation Complete ==="
log ""
log "All $NUM_VMS VMs have been prepared for installation."
log ""
log "Next steps:"
log "1. Install VNC viewer on your local machine"
log "2. For each VM, run: ./start_<vm_name>.sh install"
log "3. Connect via VNC to install Ubuntu manually"
log "4. After installation, run: ./start_<vm_name>.sh (normal boot)"
log ""
log "VM Information:"
log "- VNC Ports: 5900-$((5900 + NUM_VMS - 1))"
log "- VM Info File: $VM_INFO_FILE"
log "- Startup Scripts: start_ubuntu-vm-*.sh"
log ""
log "Example commands:"
log "  ./start_ubuntu-vm-1.sh install    # Start VM1 for installation"
log "  ./start_ubuntu-vm-1.sh           # Start VM1 after installation"
log ""
log "VNC Connection Guide:"
log "- Install VNC viewer (TigerVNC, RealVNC, etc.)"
log "- Connect to localhost:5900 (for VM1), localhost:5901 (for VM2), etc."
log "- Use the VNC passwords from $VM_INFO_FILE"