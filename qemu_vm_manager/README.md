# QEMU VM Manager for Automated Ubuntu Desktop Setup

## 1. Introduction

This project provides a suite of scripts to automate the creation, configuration, and management of multiple unique QEMU/KVM virtual machines (VMs). Each VM is set up with Ubuntu Desktop (minimal), unique hardware identifiers, resource limits, VNC access for graphical interface, an OpenVPN client configured with a unique profile, and Telegram Desktop pre-installed.

The primary script, `manage_vms.sh` (located at the root of this project), is designed to be largely self-contained. When run with `sudo`, it handles host dependency installation (for Ubuntu-based systems), Ubuntu ISO download, and all VM lifecycle stages.

For a streamlined setup on a fresh server, an external `bootstrap_vm_setup.sh` script (content provided in this README) can be used to download this project from your Git repository and initiate the `manage_vms.sh` script.

## 2. Features

*   **All-in-One Main Script (`manage_vms.sh`)**:
    *   Attempts `sudo` self-elevation if not run as root initially (though bootstrap method will typically run it as root).
    *   Installs host dependencies (QEMU, Python, jq, etc.) on Ubuntu-based systems using `apt-get`.
    *   Downloads the Ubuntu 22.04.4 Desktop AMD64 ISO if not found in the `iso/` directory.
    *   Checks KVM availability using `kvm-ok` (from `cpu-checker` package, which it installs).
    *   Attempts to add the original user (who invoked `sudo`) to `kvm` and `libvirt` groups, with a warning that a logout/login may be needed for these changes to affect that user's non-sudo QEMU operations.
*   **Automated VM Creation**: Handles the entire lifecycle from disk image creation to full guest OS setup.
*   **Unique VM Identities**: Unique MAC, UUID, BIOS Serial, varied CPU models, and slightly varied RAM for fingerprinting.
*   **Configuration Driven**: VM specs generated into JSON files by `scripts/generate_vm_configs.py`.
*   **Automated Ubuntu Installation**: Uses `scripts/preseed.cfg` for unattended Ubuntu Desktop (minimal) install (user `vmuser`, pass `userpass`).
*   **In-Guest Setup (`scripts/setup_vm_in_guest.sh`)**: Configures VNC, OpenVPN (unique profiles), and installs Telegram. Includes OpenVPN connection verification.
*   **Resource Management**: CPU limited to ~80% of one core per VM; RAM ~2GB.
*   **Access & Logging**: VNC on sequential ports (5900+); comprehensive logs from host and guest; summary in `output/vm_info.txt`.

## 3. Project Structure (Your Git Repository)

When you host this project (e.g., on GitHub), your repository root should contain the following:

```
. (Your Repository Root)
├── manage_vms.sh                # Main orchestration script (handles host setup & VM lifecycle)
├── scripts/
│   ├── generate_vm_configs.py   # Generates unique JSON configs for each VM
│   ├── preseed.cfg              # Ubuntu preseed file for automated installation
│   └── setup_vm_in_guest.sh     # Script run inside guest for setup
├── vpn/                         # ** YOU MUST CREATE AND POPULATE THIS DIRECTORY **
│   ├── vpn-1.ovpn
│   └── ... (vpn-X.ovpn up to NUM_VMS)
├── iso/                         # Created by manage_vms.sh for the downloaded ISO
├── vm_configs/                  # Created by manage_vms.sh via generate_vm_configs.py
├── vm_disks/                    # Created by manage_vms.sh for VM disk images
├── output/                      # Created by manage_vms.sh for vm_info.txt
└── README.md                    # This detailed README file
```
**Note**: The `bootstrap_vm_setup.sh` script (detailed in Section 5.1) is an *external* script. You run it on your server; it is not part of the repository structure it clones.

## 4. How It Works (Detailed Workflow)

*(This section describes the flow assuming `manage_vms.sh` is run, either directly or via the bootstrap script).*

1.  **Host Environment Setup (by `manage_vms.sh`)**:
    *   **Privilege Check & Elevation**: Ensures running as `root` (via `sudo`), re-launching itself if needed.
    *   **Package Installation**: Installs necessary host packages (`qemu-system-x86`, `qemu-utils`, `python3`, `python3-pip`, `jq`, `cpulimit`, `wget`, `cpu-checker`) using `apt-get`.
    *   **KVM Verification**: Uses `kvm-ok` to ensure KVM is usable. Exits if not.
    *   **User Group Setup**: Adds the original sudo user (e.g., `${SUDO_USER}`) to the `kvm` and `libvirt` groups. Warns that a logout/login might be needed for these group changes to affect that user's non-sudo QEMU/virsh usage (the script itself continues with `sudo`).
    *   **ISO Download**: Creates the `iso/` directory if it doesn't exist. If `iso/ubuntu-desktop.iso` is missing, it downloads the Ubuntu 22.04.4 Desktop AMD64 ISO (`https://releases.ubuntu.com/22.04/ubuntu-22.04.4-desktop-amd64.iso`) and saves it as `iso/ubuntu-desktop.iso`.
    *   **Project File Verification**: Checks for the existence of `scripts/preseed.cfg`, `scripts/setup_vm_in_guest.sh`, and all required `vpn/vpn-X.ovpn` files.

2.  **VM Configuration Generation (by `manage_vms.sh` calling `scripts/generate_vm_configs.py`)**:
    *   `scripts/generate_vm_configs.py` is run to create JSON configuration files (e.g., `vm_configs/vm-1.json`) for each VM, containing all unique parameters.

3.  **Main VM Processing Loop (in `manage_vms.sh`)**: For each VM configuration:
    *   **Disk Image**: If `vm_disks/VM_NAME.qcow2` doesn't exist, `qemu-img create` makes it. If it exists, the OS installation is skipped.
    *   **Temporary HTTP Server for OS Install**:
        *   A unique temporary directory (e.g., `/tmp/qemu_http_serve-1`) is created.
        *   The following files are placed into this directory for the VM to fetch:
            *   `vm-X-params.sh`: A dynamically generated script containing VM-specific variables (HOST_IP for guest, HTTP port, VM_ID, VNC password, OpenVPN config filename).
            *   `preseed.cfg` (copied from `scripts/`).
            *   `setup_vm_in_guest.sh` (copied from `scripts/`).
            *   The specific `vpn-X.ovpn` for the current VM (copied from `vpn/`).
        *   A Python HTTP server (`python3 -m http.server`) is started in this temporary directory.
    *   **QEMU OS Installation**:
        *   `qemu-system-x86_64` is launched with the Ubuntu ISO (`iso/ubuntu-desktop.iso`) and the newly created VM disk.
        *   The kernel command line (`-append ...`) includes:
            *   `preseed/url=http://<HOST_IP_FOR_GUEST>:<HTTP_PORT>/preseed.cfg`: Instructs the Ubuntu installer to use the preseed file served by the temporary HTTP server.
            *   `vm_setup_params_url=http://<HOST_IP_FOR_GUEST>:<HTTP_PORT>/vm-X-params.sh`: Passes the URL of the VM-specific parameters script to the installer environment.
        *   **Preseeding (`scripts/preseed.cfg`)**: This file automates the entire Ubuntu installation.
            *   **`late_command`**: This is a critical part of the preseed file. It runs *inside* the newly installed system (in a chroot environment) just before the installation finishes. This `late_command` performs these actions:
                1.  Downloads `vm-X-params.sh` from the temporary HTTP server.
                2.  Sources (`.`) `vm-X-params.sh` to load variables like `VNC_PASS`, `OVPN_CONF_FILENAME`, etc., into its environment.
                3.  Downloads `setup_vm_in_guest.sh` from the temporary HTTP server.
                4.  Makes `setup_vm_in_guest.sh` executable.
                5.  Executes `setup_vm_in_guest.sh`, passing the necessary variables (now suffixed with `_FOR_GUEST`, e.g., `VNC_PASS_FOR_GUEST`) as environment variables to it.
                6.  The exit code of `setup_vm_in_guest.sh` is propagated as the exit code of the `late_command`.
        *   The preseed configuration tells the installer to **halt** the VM upon completion.
        *   `manage_vms.sh` waits for the QEMU installation process to terminate and explicitly checks its exit code. A non-zero code indicates a failure during installation or the `late_command` (and thus `setup_vm_in_guest.sh`).
    *   **HTTP Server Cleanup**: The temporary HTTP server is stopped, and its directory is removed.
    *   **Normal VM Boot**: If installation was successful, QEMU is launched again, this time booting from the VM's disk (`-boot c`). It uses the same hardware parameters and is run daemonized (`-daemonize`). A PID file is created (e.g., `/var/run/ubuntu-vm-1.pid`).
    *   **CPU Limiting**: `cpulimit` is attached to the QEMU process PID to restrict its CPU usage.
    *   **Information Logging**: Key details of the successfully started VM are appended to `output/vm_info.txt`.

4.  **In-Guest Final Setup (by `scripts/setup_vm_in_guest.sh` executed via `late_command`)**:
    *   **VNC Server**: Configures `x11vnc` with the unique password (from `vm-X-params.sh`) and creates an XDG autostart file (`/etc/xdg/autostart/x11vnc_autostart.desktop`) so `x11vnc` starts when `vmuser` logs into the graphical session.
    *   **OpenVPN Client**: Fetches the specific `vpn-X.ovpn` file, places it as `/etc/openvpn/client/client.conf`, enables and starts the `openvpn-client@client.service`. It then performs a ping test to an external IP to verify connectivity. If this fails, `setup_vm_in_guest.sh` exits with an error.
    *   **Telegram Desktop**: Downloads the official Linux portable version, extracts it to `/opt/telegram`, creates a symlink, and a `.desktop` file for application menu integration.
    *   **Completion Flag**: Creates a flag file: `/home/vmuser/vm_setup_complete.flag`.

## 5. Installation and Execution

### 5.1. Option 1: Remote Bootstrap Installation (Recommended for Fresh Servers)
This method uses the `bootstrap_vm_setup.sh` script (content provided in Section 14) to download your main project files from your Git repository and then run the setup.

**Step 1: Host Your Project on GitHub (or similar)**
   1.  **Create Local Project Structure**: On your local machine, arrange the project files as described in Section 3 ("Project Structure"). This means `manage_vms.sh` and this `README.md` are at the root of this project directory, with `scripts/` as a subdirectory.
   2.  **Populate `vpn/` Directory**: In your local project structure, create the `vpn/` directory and place your OpenVPN configuration files inside it, named `vpn-1.ovpn`, `vpn-2.ovpn`, ..., `vpn-10.ovpn` (or up to `NUM_VMS` if you change it).
   3.  **Initialize Git and Push**:
       ```bash
       # cd /path/to/your/project_root (e.g., cd my_qemu_project)
       git init
       git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git # Replace with your new repo URL
       git add .
       git commit -m "Initial commit of QEMU VM automation project"
       git branch -M main  # Or your preferred default branch name
       git push -u origin main
       ```
   4.  Note your repository's HTTPS clone URL (e.g., `https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git`).

**Step 2: Run the Bootstrap Script on Your Target Ubuntu Server**
   1.  Log into your target Ubuntu server.
   2.  Copy the content of `bootstrap_vm_setup.sh` (from Section 14 of this README) into a new file named, for example, `bootstrap.sh` on your server.
   3.  Make it executable and run it with `sudo`:
       ```bash
       chmod +x bootstrap.sh
       sudo ./bootstrap.sh
       ```
       Alternatively, for a true one-liner if you host `bootstrap_vm_setup.sh` content raw online (e.g., GitHub Gist - ensure you trust the source):
       ```bash
       curl -sSL <URL_to_raw_bootstrap_script_content> | sudo bash -s --
       ```
   4.  The bootstrap script will prompt you to enter the HTTPS URL of the Git repository you set up in Step 1.

**Step 3: Monitor Execution**
   *   The `bootstrap_vm_setup.sh` script will clone your repository and then execute `manage_vms.sh` from within the cloned directory.
   *   `manage_vms.sh` will then take over. This entire process will take a considerable amount of time. Monitor the console output carefully.

### 5.2. Option 2: Manual Setup
If you prefer not to use the bootstrap script:

1.  **Clone or Download Project Files**: Obtain all project files (`manage_vms.sh`, `scripts/*`, this `README.md`) and place them in a project directory on your host (e.g., `~/qemu_project_manual`). Ensure the directory structure matches Section 3.
2.  **Populate `vpn/` directory** with your `vpn-X.ovpn` files inside your project directory.
3.  **Navigate to Project Directory**: `cd ~/qemu_project_manual`
4.  **Make `manage_vms.sh` Executable**: `chmod +x manage_vms.sh`
5.  **Run the Main Script with Sudo**:
    ```bash
    sudo ./manage_vms.sh
    ```
    (`manage_vms.sh` will handle host dependency installation, ISO download, etc.)

## 6. Accessing the VMs

*   **VNC**: Each VM's graphical desktop is accessible via a VNC client (e.g., TigerVNC, Remmina).
    *   Connect to `localhost:<VNC_Port_Host>`.
    *   The `VNC_Port_Host` for each VM is listed in `output/vm_info.txt` (e.g., `localhost:5900` for VM 1, `localhost:5901` for VM 2, etc.).
*   **VNC Password**: The unique VNC password for the `x11vnc` server *inside* each VM is also listed in `output/vm_info.txt`.
*   **In-VM User**: Default username `vmuser`, password `userpass` (set in `scripts/preseed.cfg`).

## 7. Error Handling and Debugging

*   **Main Script Output**: The `manage_vms.sh` (and `bootstrap_vm_setup.sh`) scripts log extensively to the console. Redirect this output to a file for review: `sudo ./bootstrap.sh > setup.log 2>&1` or `sudo ./manage_vms.sh > setup.log 2>&1`.
*   **QEMU Installation Phase**: If an installation hangs or fails, connect to the VM's VNC port shown in the `manage_vms.sh` logs. Inside the installer's VNC session, press `Alt+F4` (or cycle through virtual consoles with `Ctrl+Alt+F1/F2/F3/F4`) to view installer logs. The `DEBCONF_DEBUG=5` kernel argument (set by `manage_vms.sh`) provides verbose logging.
*   **Preseed `late_command` Log**: This critical step logs to `/target/var/log/late_command.log` *within the context of the installing system's disk image*. If installation fails here, you might need to mount the VM's `.qcow2` image to inspect this log.
*   **`setup_vm_in_guest.sh` Log**: Inside each *running* VM, this script logs to `/var/log/setup_vm_in_guest.log`.
*   **`x11vnc` Log**: Inside each *running* VM, `x11vnc` logs to `/home/vmuser/x11vnc.log`.
*   **OpenVPN Client (in Guest)**:
    *   Status: `sudo systemctl status openvpn-client@client.service`
    *   Logs: `sudo journalctl -u openvpn-client@client.service -n 50 --no-pager`
    *   The `setup_vm_in_guest.sh` log will also show results of its ping test for VPN connectivity.
*   **Common Issues**:
    *   **Permissions**: Ensure the script execution (bootstrap or manage_vms) starts with `sudo`.
    *   **Internet Connectivity**: Required for `apt`, `git clone`, ISO download, and guest package downloads.
    *   **KVM Not Enabled**: `manage_vms.sh` checks this. Ensure virtualization is enabled in host BIOS/UEFI.
    *   **Disk Space/RAM**: Insufficient host resources.
    *   **VPN File Issues**: Missing or incorrectly named `.ovpn` files in your `vpn/` directory (in your Git repo if using bootstrap, or local project dir if manual).
    *   **Typos in Git URL** (for bootstrap).

## 8. Fingerprinting Techniques Used

*   **MAC Address**: Unique, randomly generated (QEMU OUI `52:54:00` + random bytes).
*   **UUID**: Unique SMBIOS UUID per VM.
*   **BIOS Serial Number**: Unique generated string per VM.
*   **CPU Model**: Varied from a predefined list in `scripts/generate_vm_configs.py`.
*   **RAM Size**: Mostly 2GB, with slight variations for some VMs.

## 9. Resource Management

*   **CPU**: 1 core per VM. `cpulimit` restricts each QEMU process to ~80% of one host core.
*   **RAM**: ~2GB per VM (with minor variations).

## 10. Tools Used (Host & Guest)

*   **Host**: `bash`, `sudo`, `apt-get`, `git`, `qemu-system-x86_64`, `qemu-img`, `python3` (for `http.server` and `generate_vm_configs.py`), `jq`, `cpulimit`, `wget`, `cpu-checker` (`kvm-ok`), `logname`, `whoami`, `usermod`, `id`, `ps`, `kill`, `wait`, `cat`, `echo`, `chmod`, `mkdir`, `rm`, `cd`, `sleep`, `basename`.
*   **Guest (via preseed/setup script)**: `sh`, `wget`, `apt-get`, `systemctl`, `x11vnc`, `openvpn`, `tar`, `ping` (`iputils-ping`), `update-desktop-database`, `sed`, and core Linux utilities.

## 11. Customization

*   **Number of VMs**: Edit `NUM_VMS` in `manage_vms.sh` AND `scripts/generate_vm_configs.py`. Ensure enough `vpn-X.ovpn` files.
*   **VM Resources**: Modify `scripts/generate_vm_configs.py` (CPU list, RAM logic, disk size).
*   **Guest User/Password**: Edit `scripts/preseed.cfg` (`passwd/username`, `passwd/user-password-crypted`). Use `mkpasswd -m sha-512 yournewpassword` for new hash.
*   **Guest Packages**: Add to `pkgsel/include` in `preseed.cfg` or via `apt-get` in `setup_vm_in_guest.sh`.
*   **ISO URL**: Change `UBUNTU_ISO_URL` in `manage_vms.sh` if using a different ISO. Ensure preseed compatibility.

## 12. Known Limitations / Future Considerations

*   **Sequential VM Creation**: `manage_vms.sh` is sequential. Parallelization is complex.
*   **Error Recovery**: If `manage_vms.sh` is interrupted, manual cleanup of disk images, PIDs, or temp HTTP dirs might be needed.
*   **OpenVPN `auth-user-pass`**: Not handled by default; requires `setup_vm_in_guest.sh` modification.
*   **Security**: Default passwords (`userpass`, VNC passwords in `vm_info.txt`) should be changed for secure environments. `manage_vms.sh` running sensitive operations via `sudo` requires trust in the script content.

## 13. License

(Placeholder - Consider MIT or similar if sharing)
```text
MIT License

Copyright (c) [Current Year] [Your Name/Organization]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 14. `bootstrap_vm_setup.sh` Script Content
This is the content for the **external** `bootstrap_vm_setup.sh` script. You would save this script on your target server (or pipe it via `curl`), make it executable, and run it with `sudo`. It will then prompt for your Git repository URL containing the main project files (like `manage_vms.sh`, `scripts/`, etc.).

```bash
#!/bin/bash

# Bootstrap script to download and initiate the QEMU VM setup.
# This script is intended to be run on a fresh Ubuntu server.
# It will clone a Git repository containing the main 'manage_vms.sh' and its related files.

set -eo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Configuration ---
# The cloned directory will be named after the repository, or use this if parsing fails.
DEFAULT_PROJECT_CLONE_DIR="qemu_vm_automation_project"

# --- Helper Functions ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] $1"
}

ensure_sudo_for_bootstrap() {
    if [ "$(id -u)" -ne 0 ]; then
        log "This bootstrap script needs to run with sudo for initial package installation (git)."
        log "Attempting to re-launch with sudo..."
        if command -v sudo &> /dev/null; then
            # Preserve arguments passed to the script
            exec sudo bash "$0" "$@"
        else
            log "Error: sudo command not found. Please run this script as root."
            exit 1
        fi
    fi
    log "Bootstrap running with necessary privileges (UID: $(id -u))."
}

# --- Main Bootstrap Logic ---
# Ensure script arguments are passed to ensure_sudo_for_bootstrap if it re-executes
ensure_sudo_for_bootstrap "$@"

log "Updating package lists (apt-get update)..."
if ! apt-get update -y; then
    log "Error: apt-get update failed. Please check internet connection and apt sources."
    exit 1
fi
log "Package lists updated."

log "Installing git..."
if ! apt-get install -y git; then
    log "Error: Failed to install git. Cannot proceed."
    exit 1
fi
log "git installed successfully."

REPO_URL=""
while [ -z "$REPO_URL" ]; do
    read -r -p "Please enter the FULL HTTPS URL of your Git repository containing the project files (e.g., https://github.com/yourusername/your-repo-name.git): " REPO_URL
    # Basic validation for a https github URL
    if [[ ! "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+\.git$ ]]; then
        log "Invalid URL format. Expected: https://github.com/username/repository.git"
        REPO_URL=""
    fi
done

# Derive the directory name from the repo URL (e.g., your-repo-name)
PROJECT_CLONE_DIR=$(basename "$REPO_URL" .git)
if [ -z "$PROJECT_CLONE_DIR" ]; then
    log "Warning: Could not derive project name from URL. Using default: $DEFAULT_PROJECT_CLONE_DIR"
    PROJECT_CLONE_DIR="$DEFAULT_PROJECT_CLONE_DIR"
fi
log "Project will be cloned into ./${PROJECT_CLONE_DIR}"

# Handle existing directory: remove or ask? For automation, often best to remove or fail.
# For this script, let's try to be idempotent by removing if it exists.
if [ -d "$PROJECT_CLONE_DIR" ]; then
    log "Warning: Directory ./${PROJECT_CLONE_DIR} already exists. Removing it to ensure a fresh clone."
    if ! rm -rf "$PROJECT_CLONE_DIR"; then
        log "Error: Failed to remove existing directory ./${PROJECT_CLONE_DIR}. Please remove it manually and retry."
        exit 1
    fi
fi

log "Cloning repository from $REPO_URL into ./${PROJECT_CLONE_DIR}..."
if ! git clone "$REPO_URL" "$PROJECT_CLONE_DIR"; then
    log "Error: Failed to clone repository from $REPO_URL."
    exit 1
fi
log "Repository cloned successfully into ./${PROJECT_CLONE_DIR}"

# The main `manage_vms.sh` script is expected to be at the root of the cloned repository.
cd "$PROJECT_CLONE_DIR" || {
    log "Error: Failed to change directory to ./${PROJECT_CLONE_DIR} after clone.";
    exit 1;
}
log "Changed working directory to $(pwd)"

MAIN_SCRIPT_NAME="manage_vms.sh"

if [ ! -f "$MAIN_SCRIPT_NAME" ]; then
    log "Error: Main script '$MAIN_SCRIPT_NAME' not found in the root of the cloned repository ($(pwd))."
    log "Please ensure the repository you provided has '$MAIN_SCRIPT_NAME' at its top level."
    exit 1
fi

log "Making '$MAIN_SCRIPT_NAME' executable (if not already)..."
chmod +x "$MAIN_SCRIPT_NAME"

log "Executing ./${MAIN_SCRIPT_NAME} to perform all setup and VM creation..."
log "This script ('${MAIN_SCRIPT_NAME}') will handle its own specific sudo needs for its operations."
# Pass any arguments received by bootstrap_vm_setup.sh to manage_vms.sh
# We are already root here due to ensure_sudo_for_bootstrap. manage_vms.sh also has ensure_sudo.
exec "./$MAIN_SCRIPT_NAME" "$@"

log "Bootstrap process should have handed over to manage_vms.sh. This line should not be reached if exec worked."
exit 0
```
