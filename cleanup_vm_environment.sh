#!/bin/bash

# Script to clean up VMs and related files created by manage_vms.sh
# This script should typically be run from the root of the project directory
# (e.g., the directory containing manage_vms.sh, vm_disks/, etc.)

set -u # Treat unset variables as an error

# --- Configuration ---
# Default number of VMs, used for guessing HTTP server port range in logs.
# Should ideally match NUM_VMS in manage_vms.sh for log message accuracy,
# but the actual port cleanup loop uses a fixed sensible range.
NUM_VMS=10
HTTP_SERVER_PORT_BASE=8000 # Matches manage_vms.sh

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

# Assuming this script is run from the project root directory (where manage_vms.sh is)
PROJECT_ROOT_DIR="."
VM_DISKS_DIR="${PROJECT_ROOT_DIR}/vm_disks"
VM_CONFIGS_DIR="${PROJECT_ROOT_DIR}/vm_configs"
OUTPUT_DIR="${PROJECT_ROOT_DIR}/output"
ISO_DIR="${PROJECT_ROOT_DIR}/iso"
TEMP_HTTP_BASE_DIR="/tmp/qemu_http_serve" # Matches manage_vms.sh
PID_FILE_DIR="/var/run" # Where manage_vms.sh stores QEMU PIDs

log "Starting cleanup process from directory: $(pwd)"
log "This script assumes it's run from the root of your cloned project."

# 1. Stop and remove QEMU VMs based on PID files
log "Looking for QEMU PID files in ${PID_FILE_DIR}/ubuntu-vm-*.pid..."
shopt -s nullglob # Glob expands to nothing if no matches
pid_files_found_array=(${PID_FILE_DIR}/ubuntu-vm-*.pid)
shopt -u nullglob # Revert glob behavior

if [ ${#pid_files_found_array[@]} -gt 0 ]; then
    for pid_file in "${pid_files_found_array[@]}"; do
        if [ -f "$pid_file" ]; then # Should always be true due to glob behavior with nullglob off by default
            qemu_pid=$(cat "$pid_file")
            vm_name_from_pid_file=$(basename "$pid_file" .pid)
            if [[ "$qemu_pid" =~ ^[0-9]+$ ]] && ps -p "$qemu_pid" > /dev/null; then
                log "Found running QEMU VM $vm_name_from_pid_file (PID: $qemu_pid). Attempting to stop..."
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
        fi
    done
else
    log "No QEMU PID files matching pattern ${PID_FILE_DIR}/ubuntu-vm-*.pid found."
fi

# 2. Kill related cpulimit processes
log "Attempting to stop cpulimit processes..."
if pkill -9 -f "cpulimit .* -p [0-9]+"; then # Try to match cpulimit commands targeting a PID
    log "Killed cpulimit processes that were targeting a PID."
elif pkill -9 cpulimit; then # Fallback to broader pkill
    log "Killed cpulimit processes (broader match)."
else
    log "No cpulimit processes found or failed to kill."
fi

# 3. Kill lingering Python HTTP servers
log "Attempting to stop Python HTTP servers (typically on ports ${HTTP_SERVER_PORT_BASE} to $(($HTTP_SERVER_PORT_BASE + $NUM_VMS -1 )) )..."
if command -v fuser &> /dev/null; then
    killed_any_http=0
    for port_to_check in $(seq "$HTTP_SERVER_PORT_BASE" "$(($HTTP_SERVER_PORT_BASE + $NUM_VMS + 9))"); do # Check a slightly larger range just in case
        if fuser -k -n tcp "$port_to_check" > /dev/null 2>&1; then
            log "Killed process(es) on port $port_to_check using fuser."
            killed_any_http=1
        fi
    done
    if [ "$killed_any_http" -eq 0 ]; then
        log "No processes found by fuser on target ports."
    fi
else
    log "Warning: 'fuser' command not found. Attempting pkill for python http.server."
    if pkill -9 -f "python3 -m http.server"; then
        log "Killed python3 http.server processes using pkill."
    else
        log "No python3 http.server processes found by pkill. Lingering HTTP servers may need manual cleanup (e.g., 'ps aux | grep http.server')."
    fi
fi

# 4. Remove temporary HTTP server directories
shopt -s nullglob
temp_dirs_array=("${TEMP_HTTP_BASE_DIR}"-*)
shopt -u nullglob

if [ ${#temp_dirs_array[@]} -gt 0 ]; then
    log "Removing temporary HTTP server directories from ${TEMP_HTTP_BASE_DIR}-* ..."
    rm -rf "${TEMP_HTTP_BASE_DIR}"-*
    log "Temporary HTTP server directories removed."
else
    log "No temporary HTTP server directories found matching ${TEMP_HTTP_BASE_DIR}-*"
fi

# 5. Remove VM disk images
if [ -d "$VM_DISKS_DIR" ]; then
    if [ "$(ls -A $VM_DISKS_DIR 2>/dev/null)" ]; then
        log "$VM_DISKS_DIR contains files."
        read -r -p "Are you sure you want to delete all files in $VM_DISKS_DIR? [y/N]: " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            rm -rf "${VM_DISKS_DIR}"/*
            log "VM disk images removed from $VM_DISKS_DIR."
        else
            log "Skipping removal of VM disk images."
        fi
    else
        log "VM disks directory $VM_DISKS_DIR is empty. Nothing to remove."
    fi
else
    log "VM disks directory $VM_DISKS_DIR not found."
fi

# 6. Remove generated VM configurations
if [ -d "$VM_CONFIGS_DIR" ]; then
     if [ "$(ls -A $VM_CONFIGS_DIR 2>/dev/null)" ]; then
        log "$VM_CONFIGS_DIR contains files."
        read -r -p "Are you sure you want to delete all files in $VM_CONFIGS_DIR? [y/N]: " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            rm -rf "${VM_CONFIGS_DIR}"/*
            log "VM configurations removed from $VM_CONFIGS_DIR."
        else
            log "Skipping removal of VM configurations."
        fi
    else
        log "VM configs directory $VM_CONFIGS_DIR is empty. Nothing to remove."
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
# log "Checking ISO directory: $ISO_DIR..."
# if [ -d "$ISO_DIR" ] && [ "$(ls -A $ISO_DIR 2>/dev/null)" ]; then
#    read -r -p "Do you want to remove the downloaded ISO file(s) in $ISO_DIR? This will require re-downloading. [y/N]: " iso_response
#    if [[ "$iso_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
#        log "Removing ISO files from $ISO_DIR/..."
#        # rm -rf "${ISO_DIR}"/* # Or specific ISO file: rm -f "${ISO_DIR}/ubuntu-desktop.iso"
#        # For safety, let's only remove the specific ISO if it exists
#        if [ -f "${ISO_DIR}/ubuntu-desktop.iso" ]; then
#            rm -f "${ISO_DIR}/ubuntu-desktop.iso"
#            log "Removed ${ISO_DIR}/ubuntu-desktop.iso."
#        else
#            log "Specific ISO file ubuntu-desktop.iso not found in $ISO_DIR."
#        fi
#    else
#        log "Skipping removal of ISO files."
#    fi
# else
#    log "ISO directory $ISO_DIR not found or empty."
# fi

# 9. Remove stray /tmp/ubuntu-vm-*.pid files (less critical now that /var/run is used)
shopt -s nullglob
tmp_pid_files_array=(/tmp/ubuntu-vm-*.pid)
shopt -u nullglob
if [ ${#tmp_pid_files_array[@]} -gt 0 ]; then
    log "Removing any stray /tmp/ubuntu-vm-*.pid files..."
    rm -f /tmp/ubuntu-vm-*.pid
else
    log "No stray /tmp/ubuntu-vm-*.pid files found."
fi

log "Cleanup process finished."
log "Please note: If KVM group memberships were changed by manage_vms.sh, those changes are system-wide and not undone by this script."
log "Host package installations (QEMU, Python, etc.) are also not undone by this script."

exit 0
