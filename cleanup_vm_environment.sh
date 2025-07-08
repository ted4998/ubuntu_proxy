#!/bin/bash

# Script to clean up VMs and related files created by manage_vms.sh
# This script should typically be run from the root of the project directory
# (e.g., the directory containing manage_vms.sh, vm_disks/, etc.)

set -u # Treat unset variables as an error

# --- Helper Functions ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [CLEANUP] $1"
}

ensure_sudo_for_cleanup() {
    if [ "$(id -u)" -ne 0 ]; then
        log "This cleanup script needs sudo privileges to kill processes and remove some files."
        log "Please run it with sudo."
        exit 1
    fi
    log "Cleanup running with sudo privileges."
}

# --- Main Cleanup Logic ---
ensure_sudo_for_cleanup

# Assuming this script is in the same directory as manage_vms.sh, or one level above the project root.
# For simplicity, let's assume it's run from the project root where manage_vms.sh is.
PROJECT_ROOT_DIR="." # Current directory
VM_DISKS_DIR="${PROJECT_ROOT_DIR}/vm_disks"
VM_CONFIGS_DIR="${PROJECT_ROOT_DIR}/vm_configs"
OUTPUT_DIR="${PROJECT_ROOT_DIR}/output"
ISO_DIR="${PROJECT_ROOT_DIR}/iso"
TEMP_HTTP_BASE_DIR="/tmp/qemu_http_serve"
PID_FILE_DIR="/var/run" # Where manage_vms.sh stores QEMU PIDs

log "Starting cleanup process..."

# 1. Stop and remove QEMU VMs based on PID files
log "Looking for QEMU PID files in $PID_FILE_DIR/ubuntu-vm-*.pid..."
for pid_file in ${PID_FILE_DIR}/ubuntu-vm-*.pid; do
    if [ -f "$pid_file" ]; then
        qemu_pid=$(cat "$pid_file")
        vm_name_from_pid_file=$(basename "$pid_file" .pid)
        if [[ "$qemu_pid" =~ ^[0-9]+$ ]] && ps -p "$qemu_pid" > /dev/null; then
            log "Found running QEMU VM $vm_name_from_pid_file (PID: $qemu_pid). Attempting to stop..."
            # Politely ask QEMU to quit via QMP (if accessible and configured) - this is complex.
            # Forcing kill for simplicity in cleanup.
            kill -9 "$qemu_pid" # Force kill
            sleep 1
            if ps -p "$qemu_pid" > /dev/null; then
                log "Warning: Failed to kill QEMU process $qemu_pid for $vm_name_from_pid_file."
            else
                log "QEMU process $qemu_pid for $vm_name_from_pid_file stopped."
            fi
        elif [[ "$qemu_pid" =~ ^[0-9]+$ ]]; then
            log "QEMU process $qemu_pid for $vm_name_from_pid_file (from PID file) not found running."
        else
            log "Invalid PID '$qemu_pid' in $pid_file for $vm_name_from_pid_file."
        fi
        log "Removing PID file $pid_file."
        rm -f "$pid_file"
    else
        log "No QEMU PID files matching pattern found (or $pid_file is not a file if loop runs once with no match)."
        break # Exit loop if no files match
    fi
done

# 2. Kill related cpulimit processes
# This is tricky as PIDs are not directly stored.
# We can try to find cpulimit processes whose target PIDs no longer exist or match known QEMU PIDs.
# A simpler, more aggressive (but potentially risky) approach is to pkill all cpulimit.
# Let's try a more targeted pkill based on the command line if possible, or just pkill.
log "Attempting to stop cpulimit processes..."
# This will kill ALL cpulimit processes. Use with caution if other cpulimit instances are running.
if pkill -9 cpulimit; then
    log "Killed cpulimit processes."
else
    log "No cpulimit processes found or failed to kill."
fi
# More targeted: `pgrep -af cpulimit` then parse PIDs if they were limiting known QEMU PIDs (complex)

# 3. Kill lingering Python HTTP servers
# These were started on ports 8000-8009 (by default for 10 VMs)
log "Attempting to stop Python HTTP servers on ports 8000-80$(($NUM_VMS-1+8000))..."
# NUM_VMS is not defined here, assume up to 10 or check a reasonable range
# A more robust way would be to store PIDs of these servers if manage_vms.sh is modified.
# For now, use fuser (if available) or ss/netstat.
if command -v fuser &> /dev/null; then
    for port_to_check in $(seq 8000 8019); do # Check a slightly larger range
        # fuser -k -n tcp $port_to_check kills processes on that port
        if fuser -k -n tcp "$port_to_check" > /dev/null 2>&1; then
            log "Killed process(es) on port $port_to_check."
        fi
    done
else
    log "Warning: 'fuser' command not found. Cannot automatically kill processes by port. Lingering HTTP servers may need manual cleanup."
    log "  You can try: 'ps aux | grep \"python3 -m http.server\"' and 'kill <PID>' manually."
fi

# 4. Remove temporary HTTP server directories
if [ -d "$TEMP_HTTP_BASE_DIR"-* ]; then # Check if any such directories exist
    log "Removing temporary HTTP server directories from $TEMP_HTTP_BASE_DIR-*"
    rm -rf "${TEMP_HTTP_BASE_DIR}"-*
else
    log "No temporary HTTP server directories found at $TEMP_HTTP_BASE_DIR-*"
fi


# 5. Remove VM disk images
if [ -d "$VM_DISKS_DIR" ]; then
    log "Removing VM disk images from $VM_DISKS_DIR/..."
    # Add a confirmation step for safety, or make it an option
    read -r -p "Are you sure you want to delete all files in $VM_DISKS_DIR? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm -rf "${VM_DISKS_DIR}"/*
        log "VM disk images removed."
    else
        log "Skipping removal of VM disk images."
    fi
else
    log "VM disks directory $VM_DISKS_DIR not found."
fi

# 6. Remove generated VM configurations
if [ -d "$VM_CONFIGS_DIR" ]; then
    log "Removing VM configurations from $VM_CONFIGS_DIR/..."
    read -r -p "Are you sure you want to delete all files in $VM_CONFIGS_DIR? [y/N]: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm -rf "${VM_CONFIGS_DIR}"/*
        log "VM configurations removed."
    else
        log "Skipping removal of VM configurations."
    fi
else
    log "VM configs directory $VM_CONFIGS_DIR not found."
fi

# 7. Remove output file
if [ -f "${OUTPUT_DIR}/vm_info.txt" ]; then
    log "Removing output file ${OUTPUT_DIR}/vm_info.txt..."
    rm -f "${OUTPUT_DIR}/vm_info.txt"
    log "Output file removed."
else
    log "Output file ${OUTPUT_DIR}/vm_info.txt not found."
fi

# 8. Optionally remove downloaded ISO
# By default, this is commented out to save re-download time.
# read -r -p "Do you want to remove the downloaded ISO file in $ISO_DIR? This will require re-downloading it. [y/N]: " iso_response
# if [[ "$iso_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
#    if [ -d "$ISO_DIR" ]; then
#        log "Removing ISO directory $ISO_DIR/..."
#        rm -rf "${ISO_DIR}"
#        log "ISO directory removed."
#    else
#        log "ISO directory $ISO_DIR not found."
#    fi
# else
#    log "Skipping removal of ISO directory."
# fi

# 9. Remove stray /tmp/*.pid files if any (though manage_vms.sh uses /var/run now)
log "Removing any stray /tmp/ubuntu-vm-*.pid files..."
rm -f /tmp/ubuntu-vm-*.pid

log "Cleanup process finished."
log "Please note: If KVM group memberships were changed by manage_vms.sh, those changes are system-wide and not undone by this script."
log "Host package installations (QEMU, Python, etc.) are also not undone by this script."

exit 0
