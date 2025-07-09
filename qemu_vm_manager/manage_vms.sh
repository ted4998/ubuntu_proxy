#!/bin/bash

# Main script to create and manage QEMU virtual machines
# ALL-IN-ONE: Attempts to handle host dependencies and ISO download.

# --- Script Configuration & Safety ---
set -eo pipefail # Exit on error, treat unset variables as an error, and propagate pipeline errors
export DEBIAN_FRONTEND=noninteractive # Ensure apt-get doesn't prompt

# --- Constants ---
PROJECT_DIR_REALPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ISO_DIR="${PROJECT_DIR_REALPATH}/iso"
ISO_FILENAME="ubuntu-desktop.iso"
ISO_FULL_PATH="${ISO_DIR}/${ISO_FILENAME}"
# Using Ubuntu 22.04.4 LTS Desktop AMD64
UBUNTU_ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.4-desktop-amd64.iso"
UBUNTU_ISO_EXPECTED_FILENAME="ubuntu-22.04.4-desktop-amd64.iso" # Actual downloaded name before potential rename

VPN_CONFIG_DIR="${PROJECT_DIR_REALPATH}/vpn"
VM_CONFIGS_DIR="${PROJECT_DIR_REALPATH}/vm_configs"
VM_DISKS_DIR="${PROJECT_DIR_REALPATH}/vm_disks"
SCRIPTS_DIR="${PROJECT_DIR_REALPATH}/scripts"
OUTPUT_DIR="${PROJECT_DIR_REALPATH}/output"
VM_INFO_FILE="${OUTPUT_DIR}/vm_info.txt"
PRESEED_FILE="${SCRIPTS_DIR}/preseed.cfg"
GUEST_SETUP_SCRIPT_NAME="setup_vm_in_guest.sh"

NUM_VMS=10

HOST_IP_FOR_GUEST="10.0.2.2"
HTTP_SERVER_PORT_BASE=8000
TEMP_SERVE_DIR_BASE="/tmp/qemu_http_serve"

# --- Helper Functions ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [PID:$$] $1"
}

ensure_sudo() {
    if [ "$(id -u)" -ne 0 ]; then
        log "This script needs to run with sudo privileges for package installation and KVM setup."
        log "Attempting to re-launch with sudo..."
        # Preserve arguments passed to the script
        sudo bash "$0" "$@"
        exit $? # Exit with the sudo command's exit code
    fi
    log "Running with sudo privileges."
}

setup_host_environment() {
    log "=== Starting Host Environment Setup ==="

    log "Updating package lists..."
    if ! apt-get update -y; then
        log "Error: apt-get update failed. Please check your internet connection and apt sources."
        exit 1
    fi
    log "Package lists updated."

    local required_pkgs=(
        qemu-system-x86 qemu-utils python3 python3-pip jq cpulimit wget cpu-checker
    )
    log "Installing host dependencies: ${required_pkgs[*]}..."
    if ! apt-get install -y --no-install-recommends "${required_pkgs[@]}"; then
        log "Error: Failed to install all required host packages. Please check apt logs."
        exit 1
    fi
    log "Host dependencies installed successfully."

    log "Checking for KVM availability (using kvm-ok)..."
    if ! kvm-ok > /dev/null 2>&1; then
        log "Error: KVM acceleration is not available or not configured correctly (checked via kvm-ok)."
        log "Please ensure virtualization is enabled in BIOS and KVM modules are loaded."
        log "Attempting to show kvm-ok diagnostic output:"
        kvm-ok || true # Show output even if it errors, for diagnostics
        exit 1
    fi
    log "KVM acceleration is available."

    local current_user
    current_user="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"
    log "Attempting to add user '$current_user' to 'kvm' and 'libvirt' groups..."
    if id -nG "$current_user" | grep -qw "kvm" && id -nG "$current_user" | grep -qw "libvirt"; then
        log "User '$current_user' is already a member of 'kvm' and 'libvirt' groups."
    else
        usermod -aG kvm "$current_user" || log "Warning: Failed to add user $current_user to kvm group."
        usermod -aG libvirt "$current_user" || log "Warning: Failed to add user $current_user to libvirt group."
        log "User '$current_user' added to 'kvm' and 'libvirt' groups. IMPORTANT: A logout/login session for '$current_user' may be required for these group changes to take full effect for non-sudo QEMU operations."
        log "Since this script runs with sudo, it will proceed. Subsequent direct QEMU use by '$current_user' might require re-login."
    fi
    log "=== Host Environment Setup Complete (excluding ISO check, which is now in check_project_files) ==="
}

# Renamed from check_project_files_remaining to check_project_files as it now includes ISO check
check_project_files() {
    log "Checking project files (ISO, VPN configs, scripts)..."

    log "Ensuring ISO directory $ISO_DIR exists..."
    mkdir -p "$ISO_DIR" # Ensure iso directory exists before checking the file

    if [ ! -f "$ISO_FULL_PATH" ]; then
        log "Error: Ubuntu ISO not found at $ISO_FULL_PATH"
        log "Please download an Ubuntu Desktop ISO (e.g., 22.04 or 24.04), place it in the 'iso' subdirectory of your project, and name it 'ubuntu-desktop.iso'."
        exit 1
    fi
    log "Ubuntu Desktop ISO found at $ISO_FULL_PATH."

    if [ ! -f "$PRESEED_FILE" ]; then
        log "Error: Preseed file not found at $PRESEED_FILE"
        exit 1
    fi
    log "Preseed file found."

    if [ ! -f "${SCRIPTS_DIR}/${GUEST_SETUP_SCRIPT_NAME}" ]; then
        log "Error: Guest setup script not found at ${SCRIPTS_DIR}/${GUEST_SETUP_SCRIPT_NAME}"
        exit 1
    fi
    log "Guest setup script found."

    mkdir -p "$VPN_CONFIG_DIR" # Ensure VPN dir exists
    for i in $(seq 1 "$NUM_VMS"); do
        if [ ! -f "${VPN_CONFIG_DIR}/vpn-${i}.ovpn" ]; then
            log "Error: VPN config file ${VPN_CONFIG_DIR}/vpn-${i}.ovpn not found."
            log "Please ensure all required VPN files (vpn-1.ovpn to vpn-${NUM_VMS}.ovpn) are present in ${VPN_CONFIG_DIR}/"
            exit 1
        fi
    done
    log "All VPN configuration files found."
}

# --- Main Logic ---
main() {
    ensure_sudo # Make sure script is running as root

    # From here, we are running as root. PROJECT_DIR_REALPATH is reliable.
    cd "$PROJECT_DIR_REALPATH" || { log "Error: Failed to change directory to $PROJECT_DIR_REALPATH. Critical error."; exit 1; }

    log "Starting QEMU VM Manager script in $PROJECT_DIR_REALPATH."

    setup_host_environment # Handles dependencies, KVM check, user groups
    check_project_files    # Check for ISO, VPNs and other scripts

    mkdir -p "$VM_CONFIGS_DIR" "$VM_DISKS_DIR" "$OUTPUT_DIR"

    log "Generating VM configurations using ${SCRIPTS_DIR}/generate_vm_configs.py..."
    # Python script expects to be run from project root for its relative paths to work.
    if ! python3 "${SCRIPTS_DIR}/generate_vm_configs.py"; then
        log "Error: Failed to generate VM configurations. Exiting."
        exit 1
    fi
    log "VM configurations generated/updated successfully in $VM_CONFIGS_DIR."

    echo "# VM Information (Generated on $(date))" > "$VM_INFO_FILE"
    echo "# VM_Name,MAC_Address,VNC_Port_Host,VNC_Password,UUID,BIOS_Serial" >> "$VM_INFO_FILE"

    for i in $(seq 1 "$NUM_VMS"); do
        local vm_config_file="${VM_CONFIGS_DIR}/vm-${i}.json"
        if [ ! -f "$vm_config_file" ]; then
            log "Error: VM config file $vm_config_file not found. Skipping VM $i."
            continue
        fi

        log "--- Processing VM $i ($vm_name) from $vm_config_file ---"

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
        local current_http_port=$((HTTP_SERVER_PORT_BASE + i - 1))
        local current_temp_serve_dir="${TEMP_SERVE_DIR_BASE}-${vm_id}"
        local vm_params_script_name="vm-${vm_id}-params.sh"

        if [ -f "$disk_image_path" ]; then
            log "Disk image $disk_image_path already exists for VM $vm_name. Skipping installation phase."
        else
            log "=== Starting Installation Phase for VM $vm_name ==="
            log "Creating disk image ($disk_size_gb GB) at $disk_image_path..."
            if ! qemu-img create -f qcow2 "$disk_image_path" "${disk_size_gb}G"; then
                log "Error: Failed to create disk image for $vm_name. Skipping this VM."
                continue
            fi
            log "Disk image created successfully."

            log "Preparing temporary HTTP server content in $current_temp_serve_dir..."
            rm -rf "$current_temp_serve_dir"
            mkdir -p "${current_temp_serve_dir}/scripts" "${current_temp_serve_dir}/vpn"

            log "Creating VM-specific parameters script: ${current_temp_serve_dir}/${vm_params_script_name}"
            cat << EOF > "${current_temp_serve_dir}/${vm_params_script_name}"
#!/bin/sh
export HOST_IP="${HOST_IP_FOR_GUEST}"
export HTTP_PORT="${current_http_port}"
export VM_ID="${vm_id}"
export VNC_PASS="${vnc_password}"
export OVPN_CONF_FILENAME="${openvpn_config_file}"
EOF
            chmod +x "${current_temp_serve_dir}/${vm_params_script_name}"

            log "Copying guest setup script, VPN config (${openvpn_config_file}), and preseed file to serve dir..."
            cp "${SCRIPTS_DIR}/${GUEST_SETUP_SCRIPT_NAME}" "${current_temp_serve_dir}/scripts/"
            cp "${VPN_CONFIG_DIR}/${openvpn_config_file}" "${current_temp_serve_dir}/vpn/"
            cp "$PRESEED_FILE" "$current_temp_serve_dir/"
            log "Temporary content prepared."

            log "Starting temporary HTTP server for $vm_name on port $current_http_port..."
            log "Attempting to start temporary HTTP server for $vm_name on port $current_http_port in $current_temp_serve_dir..."
            # Launch in subshell, redirect stderr to a temp file to check for immediate errors like "port already in use"
            HTTP_SERVER_ERROR_LOG=$(mktemp)
            (cd "$current_temp_serve_dir" && python3 -m http.server "$current_http_port" > "${HTTP_SERVER_ERROR_LOG}" 2>&1 &)
            http_server_pid=$!

            # Give it a moment to either start or fail quickly
            sleep 2

            if ! ps -p "$http_server_pid" > /dev/null; then
                log "Error: HTTP server process (PID $http_server_pid) for $vm_name did not start or exited immediately."
                if [ -s "$HTTP_SERVER_ERROR_LOG" ]; then
                    log "HTTP Server stderr/stdout:"
                    cat "$HTTP_SERVER_ERROR_LOG"
                else
                    log "No specific error output from HTTP server captured. Check if port $current_http_port is in use or if python3 http.server works manually."
                fi
                rm -f "$HTTP_SERVER_ERROR_LOG"
                rm -rf "$current_temp_serve_dir"
                continue
            fi

            # Check if the process is indeed python
            if ! ps -p "$http_server_pid" -o comm= | grep -q "python"; then
                log "Error: Process with PID $http_server_pid for $vm_name is not a Python process. HTTP server launch likely failed."
                if [ -s "$HTTP_SERVER_ERROR_LOG" ]; then
                    log "HTTP Server stderr/stdout:"
                    cat "$HTTP_SERVER_ERROR_LOG"
                fi
                kill "$http_server_pid" 2>/dev/null || true # Attempt to kill the unexpected process
                rm -f "$HTTP_SERVER_ERROR_LOG"
                rm -rf "$current_temp_serve_dir"
                continue
            fi

            # Check if server produced immediate errors (e.g. port in use) even if process started
            # Python's http.server usually prints "Serving HTTP on 0.0.0.0 port XXXX" on success to stdout.
            # If it prints an error to stderr (like address already in use) and exits, the PID might be caught briefly.
            # The redirection to HTTP_SERVER_ERROR_LOG captures both.
            if [ -s "$HTTP_SERVER_ERROR_LOG" ] && grep -E "Address already in use|Errno 98" "$HTTP_SERVER_ERROR_LOG"; then
                log "Error: HTTP server for $vm_name failed to start, likely port $current_http_port is already in use."
                log "HTTP Server output:"
                cat "$HTTP_SERVER_ERROR_LOG"
                kill "$http_server_pid" 2>/dev/null || true
                rm -f "$HTTP_SERVER_ERROR_LOG"
                rm -rf "$current_temp_serve_dir"
                continue
            fi

            rm -f "$HTTP_SERVER_ERROR_LOG" # Clean up log if no critical error found yet
            log "Temporary HTTP server (PID: $http_server_pid) for $vm_name appears to be running."

            log "Starting Ubuntu installation for $vm_name. This will take a while..."
            log "  Installation VNC: localhost:$vnc_port_host (Display ID :$((vnc_port_host - 5900)))"

            local preseed_url="http://${HOST_IP_FOR_GUEST}:${current_http_port}/preseed.cfg"
            local params_url="http://${HOST_IP_FOR_GUEST}:${current_http_port}/${vm_params_script_name}"
            local vnc_display_id=$((vnc_port_host - 5900))

            local qemu_install_cmd=(
                qemu-system-x86_64 -enable-kvm -m "${ram_mb}M" -smp 1 -cpu "$cpu_model"
                -uuid "$vm_uuid" -smbios "type=1,serial=${bios_serial}"
                -drive "file=${disk_image_path},format=qcow2,if=virtio" -cdrom "$ISO_FULL_PATH" -boot d
                -netdev "user,id=net0,hostfwd=tcp::${vnc_port_host}-:5900"
                -device "virtio-net-pci,netdev=net0,mac=${mac_address}"
                -vnc ":${vnc_display_id}" -k en-us -machine q35,accel=kvm
                -serial mon:stdio -display none
                -append "auto=true priority=critical quiet splash --- preseed/url=${preseed_url} vm_setup_params_url=${params_url} DEBCONF_DEBUG=5"
            )

            log "Executing QEMU for installation: ${qemu_install_cmd[*]}"
            set +e
            "${qemu_install_cmd[@]}"
            qemu_exit_code=$?
            set -e

            if [ $qemu_exit_code -ne 0 ]; then
                log "Error: QEMU installation for $vm_name exited with code $qemu_exit_code."
                log "  Installation may have failed. Check VNC console / QEMU output / preseed logs."
            else
                log "Installation for $vm_name finished (QEMU exited with code 0)."
            fi

            log "Stopping temporary HTTP server for $vm_name (PID: $http_server_pid)..."
            kill "$http_server_pid" || log "Warning: Failed to kill HTTP server PID $http_server_pid (may have already exited)."
            wait "$http_server_pid" 2>/dev/null || true
            rm -rf "$current_temp_serve_dir"
            log "Temporary HTTP server stopped and files cleaned up."

            if [ $qemu_exit_code -ne 0 ]; then # If install failed, skip further setup for this VM
                log "Skipping normal boot for $vm_name due to installation failure."
                continue
            fi
            log "=== Installation Phase for VM $vm_name Completed ==="
        fi

        log "=== Starting Normal Boot for VM $vm_name ==="
        local vnc_display_id_normal=$((vnc_port_host - 5900))
        local pid_file="/var/run/${vm_name}.pid" # Using /var/run, ensure script has perms (it does via sudo)
        rm -f "$pid_file"

        qemu-system-x86_64 \
            -enable-kvm -m "${ram_mb}M" -smp 1 -cpu "$cpu_model" \
            -uuid "$vm_uuid" -smbios "type=1,serial=${bios_serial}" \
            -drive "file=${disk_image_path},format=qcow2,if=virtio" -boot c \
            -netdev "user,id=net0,hostfwd=tcp::${vnc_port_host}-:5900" \
            -device "virtio-net-pci,netdev=net0,mac=${mac_address}" \
            -vnc ":${vnc_display_id_normal},password" -k en-us \
            -machine q35,accel=kvm \
            -monitor "telnet::${vnc_port_host//59/44}1,server,nowait" \
            -qmp "tcp:localhost:${vnc_port_host//59/45}1,server,nowait" \
            -pidfile "$pid_file" -daemonize

        log "VM $vm_name daemonizing. Waiting up to 30s for PID file $pid_file..."
        local wait_time=0
        while [ ! -s "$pid_file" ] && [ "$wait_time" -lt 30 ]; do
            sleep 1; wait_time=$((wait_time + 1))
            if [ $((wait_time % 5)) -eq 0 ]; then log "Still waiting for PID file for $vm_name... ($wait_time s)"; fi
        done

        if [ ! -s "$pid_file" ]; then
            log "Error: PID file $pid_file for $vm_name not found/empty after 30s. VM may have failed to daemonize."
            continue
        fi

        local qemu_pid; qemu_pid=$(cat "$pid_file")
        if ! [[ "$qemu_pid" =~ ^[0-9]+$ ]]; then
            log "Error: PID file $pid_file content ('$qemu_pid') is not a valid PID for $vm_name. Cleanup PID file."
            rm -f "$pid_file"; continue
        fi

        if ! ps -p "$qemu_pid" > /dev/null; then
            log "Error: QEMU process $qemu_pid for $vm_name (from PID file) is not running. Cleanup PID file."
            rm -f "$pid_file"; continue
        fi
        log "VM $vm_name running with PID $qemu_pid."

        log "Applying CPU limit (target 80% of 1 core) to PID $qemu_pid for $vm_name..."
        if ! cpulimit -p "$qemu_pid" -l 80 -b; then
            log "Warning: cpulimit failed for $vm_name (PID $qemu_pid). May need permissions or process died."
        else
            log "cpulimit applied successfully to $vm_name (PID $qemu_pid)."
        fi

        log "VM $vm_name setup on host complete. Details logged to $VM_INFO_FILE."
        log "  Name: $vm_name, MAC: $mac_address, Host VNC: localhost:$vnc_port_host, In-Guest VNC Pass: ${vnc_password}, PID: $qemu_pid"

        echo "${vm_name},${mac_address},${vnc_port_host},${vnc_password},${vm_uuid},${bios_serial}" >> "$VM_INFO_FILE"
        log "=== Normal Boot for VM $vm_name Completed ==="
        log "--- Finished processing for VM $vm_name ---"
    done

    log "All VM processing finished. Check $VM_INFO_FILE for summary."
    log "VMs may need a few minutes to fully boot and complete all guest setup tasks (OpenVPN, Telegram)."
    log "Access VMs via VNC: localhost:PORT (e.g., localhost:5900, localhost:5901, ...)."
    log "If KVM group memberships were changed, the original user ($SUDO_USER) may need to log out and back in for direct (non-sudo) QEMU/virsh usage."
}

# --- Script Execution ---
main "$@" # Pass all script arguments to main

exit 0
EOF
