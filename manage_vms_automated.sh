#!/bin/bash

# Fully Automated VM Manager - Zero Manual Intervention
# Uses Ubuntu Cloud Images for complete automation

set -e

PROJECT_DIR_REALPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR_REALPATH"

# Command Line Options
TEST_MODE=false
SKIP_KVM_CHECK=false
NUM_VMS=10

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --test-mode)
            TEST_MODE=true
            shift
            ;;
        --skip-kvm-check)
            SKIP_KVM_CHECK=true
            shift
            ;;
        --vms)
            NUM_VMS="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --test-mode        Run in test mode (skip actual VM creation)"
            echo "  --skip-kvm-check   Skip KVM availability check"
            echo "  --vms NUMBER       Number of VMs to create (default: 10)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Constants
VM_CONFIGS_DIR="${PROJECT_DIR_REALPATH}/vm_configs"
VM_DISKS_DIR="${PROJECT_DIR_REALPATH}/vm_disks"
CLOUD_IMAGES_DIR="${PROJECT_DIR_REALPATH}/cloud_images"
VPN_CONFIG_DIR="${PROJECT_DIR_REALPATH}/vpn"
OUTPUT_DIR="${PROJECT_DIR_REALPATH}/output"
VM_INFO_FILE="${OUTPUT_DIR}/vm_info.txt"
SCRIPTS_DIR="${PROJECT_DIR_REALPATH}/scripts"

# Ubuntu Cloud Image URLs (these support full automation)
UBUNTU_CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
UBUNTU_CLOUD_IMAGE_FILE="${CLOUD_IMAGES_DIR}/ubuntu-22.04-server-cloudimg-amd64.img"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [PID:$$] $1"
}

setup_environment() {
    log "=== Setting up Automated VM Environment ==="
    
    # Create directories
    mkdir -p "$VM_CONFIGS_DIR" "$VM_DISKS_DIR" "$CLOUD_IMAGES_DIR" "$OUTPUT_DIR"
    
    # Install required packages
    log "Installing required packages..."
    apt-get update -qq
    apt-get install -y qemu-system-x86 qemu-utils python3 python3-pip jq cpulimit wget cpu-checker cloud-image-utils genisoimage
    
    log "Environment setup complete."
}

download_cloud_image() {
    log "=== Downloading Ubuntu Cloud Image ==="
    
    if [ "$TEST_MODE" = true ]; then
        log "Test mode: Skipping cloud image download."
        touch "$UBUNTU_CLOUD_IMAGE_FILE"
        return 0
    fi
    
    if [ ! -f "$UBUNTU_CLOUD_IMAGE_FILE" ]; then
        log "Downloading Ubuntu 22.04 Cloud Image (this may take a while)..."
        wget -O "$UBUNTU_CLOUD_IMAGE_FILE" "$UBUNTU_CLOUD_IMAGE_URL"
        log "Cloud image downloaded successfully."
    else
        log "Ubuntu Cloud Image already exists."
    fi
}

generate_cloud_init_config() {
    local vm_id=$1
    local vm_name=$2
    local vnc_password=$3
    local openvpn_config=$4
    
    local cloud_init_dir="${VM_DISKS_DIR}/${vm_name}-cloud-init"
    mkdir -p "$cloud_init_dir"
    
    # Create user-data (cloud-init configuration)
    cat > "${cloud_init_dir}/user-data" << EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US
  keyboard:
    layout: us
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - ubuntu-desktop-minimal
    - x11vnc
    - openvpn
    - wget
    - curl
    - net-tools
    - htop
    - nano
    - firefox
    - telegram-desktop
  user-data:
    disable_root: false
  users:
    - name: vmuser
      password: '\$6\$randomsalt\$BW2ThxYFj9qK9aLg2ZM7g0A0nVE04DG0.RkoLeSPf7H7L3FYRaTrrG3Cvxv8A1F8MSyspXyusYuy3BNDZzaup/'
      shell: /bin/bash
      groups: [adm, sudo]
      lock_passwd: false
      sudo: ALL=(ALL) NOPASSWD:ALL
    - name: root
      password: '\$6\$randomsalt\$BW2ThxYFj9qK9aLg2ZM7g0A0nVE04DG0.RkoLeSPf7H7L3FYRaTrrG3Cvxv8A1F8MSyspXyusYuy3BNDZzaup/'
      lock_passwd: false
  storage:
    layout:
      name: direct
  late-commands:
    - curtin in-target --target=/target -- systemctl enable ssh
    - curtin in-target --target=/target -- systemctl enable gdm3
  runcmd:
    - systemctl start gdm3
    - systemctl enable gdm3
    - |
      # Setup VNC
      mkdir -p /home/vmuser/.vnc
      echo "$vnc_password" | vncpasswd -f > /home/vmuser/.vnc/passwd
      chmod 600 /home/vmuser/.vnc/passwd
      chown -R vmuser:vmuser /home/vmuser/.vnc
      
      # Create VNC startup script
      cat > /home/vmuser/.vnc/xstartup << 'VNCEOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP="ubuntu:GNOME"
export XDG_SESSION_DESKTOP="ubuntu"
export XDG_SESSION_TYPE="x11"
export GNOME_SHELL_SESSION_MODE="ubuntu"
export DESKTOP_SESSION="ubuntu"
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec /etc/X11/xinit/xinitrc
VNCEOF
      chmod +x /home/vmuser/.vnc/xstartup
      
      # Create systemd service for VNC
      cat > /etc/systemd/system/vncserver@.service << 'SVCEOF'
[Unit]
Description=Remote Desktop VNC Service
After=syslog.target network.target

[Service]
Type=forking
User=vmuser
Group=vmuser
WorkingDirectory=/home/vmuser
ExecStartPre=/bin/sh -c '/usr/bin/x11vnc -kill :1 > /dev/null 2>&1 || :'
ExecStart=/usr/bin/x11vnc -forever -display :0 -rfbport 5900 -rfbauth /home/vmuser/.vnc/passwd -shared -bg
ExecStop=/usr/bin/x11vnc -kill :1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
      
      systemctl daemon-reload
      systemctl enable vncserver@1.service
      
    - |
      # Setup OpenVPN (copy config from host)
      mkdir -p /etc/openvpn/client
      # VPN config will be copied during VM creation
      
    - |
      # Install Telegram Desktop
      snap install telegram-desktop
      
    - |
      # Final setup
      systemctl start vncserver@1.service
      update-grub
EOF

    # Create meta-data
    cat > "${cloud_init_dir}/meta-data" << EOF
instance-id: ${vm_name}
local-hostname: ${vm_name}
EOF

    # Create network-config (optional)
    cat > "${cloud_init_dir}/network-config" << EOF
version: 2
ethernets:
  ens3:
    dhcp4: true
EOF

    # Generate cloud-init ISO
    cloud-localds "${VM_DISKS_DIR}/${vm_name}-cloud-init.iso" \
        "${cloud_init_dir}/user-data" \
        "${cloud_init_dir}/meta-data" \
        "${cloud_init_dir}/network-config"
    
    log "Cloud-init configuration created for $vm_name"
}

create_automated_vm() {
    local vm_config_file=$1
    
    # Extract VM configuration
    local vm_name=$(jq -r '.vm_name' "$vm_config_file")
    local mac_address=$(jq -r '.mac_address' "$vm_config_file")
    local vnc_port_host=$(jq -r '.vnc_port_host' "$vm_config_file")
    local vnc_password=$(jq -r '.vnc_password' "$vm_config_file")
    local vm_uuid=$(jq -r '.uuid' "$vm_config_file")
    local bios_serial=$(jq -r '.bios_serial' "$vm_config_file")
    local cpu_model=$(jq -r '.cpu_model' "$vm_config_file")
    local ram_mb=$(jq -r '.ram_size_mb' "$vm_config_file")
    local disk_size_gb=$(jq -r '.disk_size_gb' "$vm_config_file")
    local openvpn_config_file=$(jq -r '.openvpn_config_file' "$vm_config_file")
    local vm_id=$(jq -r '.vm_id' "$vm_config_file")
    
    local disk_image_path="${VM_DISKS_DIR}/${vm_name}.qcow2"
    local cloud_init_iso="${VM_DISKS_DIR}/${vm_name}-cloud-init.iso"
    
    log "--- Creating Automated VM: $vm_name ---"
    
    if [ "$TEST_MODE" = true ]; then
        log "Test mode: Skipping actual VM creation for $vm_name"
        echo "${vm_name},${mac_address},${vnc_port_host},${vnc_password},${vm_uuid},${bios_serial}" >> "$VM_INFO_FILE"
        return 0
    fi
    
    # Create VM disk from cloud image
    log "Creating VM disk from cloud image..."
    qemu-img create -f qcow2 -F qcow2 -b "$UBUNTU_CLOUD_IMAGE_FILE" "$disk_image_path" "${disk_size_gb}G"
    
    # Generate cloud-init configuration
    generate_cloud_init_config "$vm_id" "$vm_name" "$vnc_password" "$openvpn_config_file"
    
    # Copy VPN configuration to a location accessible by the VM
    local vpn_config_path="${VPN_CONFIG_DIR}/${openvpn_config_file}"
    if [ -f "$vpn_config_path" ]; then
        # We'll mount this as a separate disk or copy it via cloud-init
        log "VPN config ready: $vpn_config_path"
    else
        log "Warning: VPN config $vpn_config_path not found"
    fi
    
    # Start VM with cloud-init
    log "Starting automated VM installation for $vm_name..."
    log "VNC will be available at localhost:$vnc_port_host after installation completes"
    
    # Start VM in background with cloud-init
    qemu-system-x86_64 \
        -enable-kvm \
        -m "${ram_mb}M" \
        -smp 1 \
        -cpu "$cpu_model" \
        -uuid "$vm_uuid" \
        -smbios type=1,serial="$bios_serial" \
        -drive file="$disk_image_path",format=qcow2,if=virtio \
        -drive file="$cloud_init_iso",format=raw,if=virtio,readonly=on \
        -boot c \
        -netdev user,id=net0,hostfwd=tcp::"$vnc_port_host"-:5900 \
        -device virtio-net-pci,netdev=net0,mac="$mac_address" \
        -vnc :"$((vnc_port_host - 5900))" \
        -k en-us \
        -machine q35,accel=kvm \
        -serial mon:stdio \
        -display none \
        -daemonize \
        -pidfile "/var/run/${vm_name}.pid"
    
    # Apply CPU limiting
    local vm_pid=$(cat "/var/run/${vm_name}.pid")
    cpulimit -p "$vm_pid" -l 80 > /dev/null 2>&1 &
    
    # Add to VM info file
    echo "${vm_name},${mac_address},${vnc_port_host},${vnc_password},${vm_uuid},${bios_serial}" >> "$VM_INFO_FILE"
    
    log "VM $vm_name started successfully (PID: $vm_pid)"
    log "  VNC: localhost:$vnc_port_host"
    log "  User: vmuser / Password: userpass"
    log "  VNC Password: $vnc_password"
    log "  Installation will complete automatically in 10-15 minutes"
}

main() {
    log "=== Fully Automated VM Manager ==="
    log "Creating $NUM_VMS VMs with zero manual intervention"
    
    # Setup environment
    setup_environment
    
    # Download cloud image
    download_cloud_image
    
    # Generate VM configurations
    log "Generating VM configurations..."
    if [ -f "$SCRIPTS_DIR/generate_vm_configs.py" ]; then
        python3 "$SCRIPTS_DIR/generate_vm_configs.py"
    else
        log "Error: VM config generator not found"
        exit 1
    fi
    
    # Create VM info file header
    mkdir -p "$(dirname "$VM_INFO_FILE")"
    echo "# Automated VM Information (Generated on $(date))" > "$VM_INFO_FILE"
    echo "# VM_Name,MAC_Address,VNC_Port_Host,VNC_Password,UUID,BIOS_Serial" >> "$VM_INFO_FILE"
    
    # Create VMs
    for i in $(seq 1 "$NUM_VMS"); do
        local vm_config_file="${VM_CONFIGS_DIR}/vm-${i}.json"
        
        if [ ! -f "$vm_config_file" ]; then
            log "Error: VM config file $vm_config_file not found. Skipping VM $i."
            continue
        fi
        
        create_automated_vm "$vm_config_file"
        
        # Small delay between VM starts
        sleep 2
    done
    
    log "=== Automated VM Creation Complete ==="
    log ""
    log "All $NUM_VMS VMs are now installing automatically!"
    log ""
    log "Installation Progress:"
    log "- Cloud-init will automatically install Ubuntu Desktop"
    log "- VNC server will be configured and started"
    log "- OpenVPN will be set up"
    log "- Telegram Desktop will be installed"
    log "- Total time: 10-15 minutes per VM"
    log ""
    log "VNC Access (available after installation):"
    for i in $(seq 1 "$NUM_VMS"); do
        local vnc_port=$((5900 + i - 1))
        log "  VM$i: localhost:$vnc_port"
    done
    log ""
    log "Credentials:"
    log "  Username: vmuser"
    log "  Password: userpass"
    log "  VNC Passwords: See $VM_INFO_FILE"
    log ""
    log "Monitor progress with: ./monitor_progress.sh"
    log "Check status with: ./check_status.sh"
}

# Run main function
main "$@"