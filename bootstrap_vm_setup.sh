#!/bin/bash

# Bootstrap script to download and initiate the QEMU VM setup.
# This script is intended to be run on a fresh Ubuntu server.

set -eo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Configuration ---
DEFAULT_PROJECT_DIR_NAME="qemu_vm_manager_project" # Directory where the project will be cloned

# --- Helper Functions ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] $1"
}

ensure_sudo_for_bootstrap() {
    if [ "$(id -u)" -ne 0 ]; then
        log "This bootstrap script needs to run with sudo for initial package installation (git)."
        log "Please run it with sudo, or it will attempt to re-launch with sudo."
        # Attempt to re-launch with sudo, preserving arguments
        # However, for curl | bash, direct sudo might be needed by the user.
        # This re-launch is more for saved script execution.
        if command -v sudo &> /dev/null; then
            exec sudo bash "$0" "$@"
        else
            log "Error: sudo command not found. Please run this script as root."
            exit 1
        fi
    fi
    log "Bootstrap running with necessary privileges."
}

# --- Main Bootstrap Logic ---
ensure_sudo_for_bootstrap "$@" # Pass all args

log "Updating package lists..."
if ! apt-get update -y; then
    log "Error: apt-get update failed. Please check internet connection and apt sources."
    exit 1
fi

log "Installing git..."
if ! apt-get install -y git; then
    log "Error: Failed to install git. Cannot proceed."
    exit 1
fi
log "git installed successfully."

REPO_URL=""
while [ -z "$REPO_URL" ]; do
    read -r -p "Please enter the FULL HTTPS URL of your qemu_vm_manager Git repository (e.g., https://github.com/yourusername/your-repo-name.git): " REPO_URL
    # Basic validation for a https github URL
    if [[ ! "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+\.git$ ]]; then
        log "Invalid URL format. It should look like: https://github.com/username/repository.git"
        REPO_URL=""
    fi
done

# Try to derive a project directory name from the URL, fallback to default
PROJECT_DIR_NAME=$(basename "$REPO_URL" .git)
if [ -z "$PROJECT_DIR_NAME" ]; then
    PROJECT_DIR_NAME="$DEFAULT_PROJECT_DIR_NAME"
fi
log "Project will be cloned into ./${PROJECT_DIR_NAME}"


if [ -d "$PROJECT_DIR_NAME" ]; then
    log "Warning: Directory ./${PROJECT_DIR_NAME} already exists. Attempting to pull latest changes."
    cd "$PROJECT_DIR_NAME" || { log "Error: Could not cd into existing $PROJECT_DIR_NAME"; exit 1; }
    if git pull; then
        log "Successfully pulled latest changes from $REPO_URL."
    else
        log "Warning: 'git pull' failed in existing directory. Continuing with current state or please resolve manually."
    fi
    # Ensure we are at the root of the cloned repo for the next step
    # (git pull should leave us there, but explicit cd is safer if it was a fresh clone path)
    cd ..
fi

if [ ! -d "$PROJECT_DIR_NAME" ]; then
    log "Cloning repository from $REPO_URL into ./${PROJECT_DIR_NAME}..."
    if ! git clone "$REPO_URL" "$PROJECT_DIR_NAME"; then
        log "Error: Failed to clone repository from $REPO_URL."
        exit 1
    fi
    log "Repository cloned successfully."
fi

cd "$PROJECT_DIR_NAME" || { log "Error: Failed to change directory to ./${PROJECT_DIR_NAME} after clone/pull."; exit 1; }

MAIN_SCRIPT_PATH="./manage_vms.sh" # Assuming manage_vms.sh is in the root of the cloned repo

if [ ! -f "$MAIN_SCRIPT_PATH" ]; then
    log "Error: Main script '$MAIN_SCRIPT_PATH' not found in the cloned repository."
    log "Please ensure the repository structure is correct and '$MAIN_SCRIPT_PATH' exists at the root."
    exit 1
fi

log "Making $MAIN_SCRIPT_PATH executable (if not already)..."
chmod +x "$MAIN_SCRIPT_PATH"

log "Executing $MAIN_SCRIPT_PATH to perform all setup and VM creation..."
log "This script will handle its own sudo elevation if needed for its internal operations."
# Pass any arguments received by bootstrap_vm_setup.sh to manage_vms.sh
# manage_vms.sh handles its own sudo elevation for its specific tasks.
# We are already root here due to ensure_sudo_for_bootstrap for git install.
exec "./$MAIN_SCRIPT_PATH" "$@"

log "Bootstrap process complete. manage_vms.sh has taken over."
exit 0 # Should be unreachable due to exec, but good practice.
