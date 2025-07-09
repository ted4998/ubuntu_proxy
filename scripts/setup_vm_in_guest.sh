#!/bin/bash

# Script to be run inside the VM after preseed installation.
# It receives VNC_PASS_FOR_GUEST, OVPN_CONF_FILENAME_FOR_GUEST, VM_ID_FOR_GUEST,
# HOST_IP_FOR_GUEST, HTTP_PORT_FOR_GUEST as environment variables.

# Exit immediately if a command exits with a non-zero status.
set -e

LOG_FILE="/var/log/setup_vm_in_guest.log"
# Send stdout and stderr to the log file and to the console
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "Starting setup_vm_in_guest.sh at $(date)"
echo "VM_ID: ${VM_ID_FOR_GUEST}"
echo "VNC Password: [REDACTED]" # Do not log actual password
echo "OpenVPN Config Filename: ${OVPN_CONF_FILENAME_FOR_GUEST}"
echo "Host IP for fetching: ${HOST_IP_FOR_GUEST}"
echo "Host HTTP Port for fetching: ${HTTP_PORT_FOR_GUEST}"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root. Exiting."
  exit 1
fi

# Wait for network and services to be more reliably up.
# Especially important if this script runs very early in boot.
echo "Waiting for 30 seconds for network and services to settle..."
sleep 30

# Ensure apt sources are up to date before installing anything critical
echo "Updating package lists..."
apt-get update -y || {
    echo "Error: apt-get update failed. This might affect package installations. Exiting."
    exit 1
}

# --- VNC Setup (x11vnc) ---
echo "Setting up x11vnc..."
X11VNC_PASSWORD_FILE="/etc/x11vnc.pass"
# Ensure the directory for the password file exists, though /etc should.
mkdir -p "$(dirname "$X11VNC_PASSWORD_FILE")"
echo "${VNC_PASS_FOR_GUEST}" | x11vnc -storepasswd -f "${X11VNC_PASSWORD_FILE}"
# x11vnc may run as vmuser if started from user session, but here we make root own it.
# For system-wide autostart, root ownership of the password file is fine if x11vnc is run as root.
# If x11vnc is to be run as vmuser by the autostart mechanism, vmuser needs read access.
chown root:root "${X11VNC_PASSWORD_FILE}"
chmod 400 "${X11VNC_PASSWORD_FILE}" # Only readable by root

# Using XDG autostart for x11vnc - this starts when vmuser's desktop session begins.
# This is generally more reliable with display managers like LightDM.
AUTOSTART_DIR="/etc/xdg/autostart"
mkdir -p "${AUTOSTART_DIR}"
cat << EOF > "${AUTOSTART_DIR}/x11vnc_autostart.desktop"
[Desktop Entry]
Type=Application
Name=X11VNC Server Autostart
Comment=Autostart X11VNC for user vmuser
Exec=/usr/bin/x11vnc -forever -loop -noxdamage -repeat -rfbauth ${X11VNC_PASSWORD_FILE} -rfbport 5900 -shared -o /var/log/x11vnc.log -display :0
StartupNotify=false
Terminal=false
Hidden=false
EOF
# x11vnc log will be written by the user running the X session (vmuser)
# So /var/log/x11vnc.log needs to be writable by vmuser or x11vnc run as root.
# Let's make the log writable by all for simplicity, or choose /home/vmuser/x11vnc.log
# Changed log path to /var/log/x11vnc.log and x11vnc will likely run as vmuser via autostart.
# The Exec line in .desktop will run as vmuser. So password file must be readable by vmuser.
# Let's adjust password file permissions.
chown vmuser:vmuser "${X11VNC_PASSWORD_FILE}"
chmod 400 "${X11VNC_PASSWORD_FILE}" # Readable by owner (vmuser) only

# Log for x11vnc itself, ensure vmuser can write to it.
touch /home/vmuser/x11vnc.log
chown vmuser:vmuser /home/vmuser/x11vnc.log
# Update .desktop file to use this log path
sed -i 's|-o /var/log/x11vnc.log|-o /home/vmuser/x11vnc.log|' "${AUTOSTART_DIR}/x11vnc_autostart.desktop"

echo "x11vnc configured to autostart with user session (logs to /home/vmuser/x11vnc.log)."

# --- OpenVPN Setup ---
echo "Setting up OpenVPN..."
OPENVPN_CONFIG_BASE_DIR="/etc/openvpn/client" # Standard directory for systemd client configs
mkdir -p "${OPENVPN_CONFIG_BASE_DIR}"
# Use a descriptive name for the config file, e.g., from OVPN_CONF_FILENAME_FOR_GUEST
# but systemd service expects 'client.conf' for openvpn-client@client.service generally.
# Let's stick to client.conf for the generic service unit.
OPENVPN_EFFECTIVE_CONF_NAME="client" # This will result in /etc/openvpn/client/client.conf
TARGET_OPENVPN_CONF_FILE="${OPENVPN_CONFIG_BASE_DIR}/${OPENVPN_EFFECTIVE_CONF_NAME}.conf"

VPN_FILE_ON_HOST_URL="http://${HOST_IP_FOR_GUEST}:${HTTP_PORT_FOR_GUEST}/vpn/${OVPN_CONF_FILENAME_FOR_GUEST}"

echo "Fetching OpenVPN config: ${VPN_FILE_ON_HOST_URL} to ${TARGET_OPENVPN_CONF_FILE}"
if ! wget --tries=3 --timeout=45 -O "${TARGET_OPENVPN_CONF_FILE}" "${VPN_FILE_ON_HOST_URL}"; then
    echo "Error: Failed to download OpenVPN configuration: ${OVPN_CONF_FILENAME_FOR_GUEST}. Exiting."
    exit 1
fi
echo "OpenVPN config downloaded successfully."
chmod 600 "${TARGET_OPENVPN_CONF_FILE}" # Secure permissions

echo "Enabling and starting OpenVPN service (openvpn-client@${OPENVPN_EFFECTIVE_CONF_NAME})..."
systemctl enable "openvpn-client@${OPENVPN_EFFECTIVE_CONF_NAME}.service"
systemctl start "openvpn-client@${OPENVPN_EFFECTIVE_CONF_NAME}.service"

echo "Waiting a few seconds for OpenVPN to establish connection (up to 30s)..."
OPENCONNECT_CHECK_STATUS=1
for i in {1..6}; do # Check every 5 seconds for 30 seconds
    sleep 5
    if systemctl is-active --quiet "openvpn-client@${OPENVPN_EFFECTIVE_CONF_NAME}.service"; then
        echo "OpenVPN service is active. Checking internet connectivity via VPN..."
        # Ping a reliable external IP. Adjust count and timeout as needed.
        # Ensure ping is installed (net-tools should include it, but good to be sure or add iputils-ping)
        if ping -c 2 -W 5 1.1.1.1 > /dev/null 2>&1 || ping -c 2 -W 5 8.8.8.8 > /dev/null 2>&1; then
            echo "SUCCESS: Internet connectivity via VPN confirmed."
            OPENCONNECT_CHECK_STATUS=0
            break
        else
            echo "Warning: Ping test failed. VPN might not be routing correctly or no internet. Attempt $i/6."
        fi
    else
        echo "Warning: OpenVPN service (openvpn-client@${OPENVPN_EFFECTIVE_CONF_NAME}) is not active. Attempt $i/6 to check again."
    fi
done

if [ $OPENCONNECT_CHECK_STATUS -ne 0 ]; then
    echo "Error: OpenVPN connection could not be verified after 30 seconds."
    echo "OpenVPN service status:"
    systemctl status "openvpn-client@${OPENVPN_EFFECTIVE_CONF_NAME}.service" --no-pager || true
    echo "Last 20 lines of journal for OpenVPN:"
    journalctl -u "openvpn-client@${OPENVPN_EFFECTIVE_CONF_NAME}.service" -n 20 --no-pager || true
    # Consider adding `ip addr show` and `ip route show` for debugging info here.
    echo "Current IP Addresses:"
    ip addr show
    echo "Current Routes:"
    ip route show
    echo "Exiting due to OpenVPN verification failure."
    exit 1 # Critical failure
fi

# --- Telegram Installation ---
echo "Installing Telegram Desktop..."
# Using the official portable version for simplicity and to avoid snap/repo issues in scripts
TELEGRAM_URL="https://telegram.org/dl/desktop/linux" # This is a tsetup.tar.xz file
TELEGRAM_DIR="/opt/telegram"
TELEGRAM_DESKTOP_FILE="/usr/share/applications/telegramdesktop.desktop"

# Download and extract
mkdir -p /tmp/telegram_install
cd /tmp/telegram_install

echo "Downloading Telegram from ${TELEGRAM_URL}..."
if wget --tries=3 --timeout=120 -O tsetup.tar.xz "${TELEGRAM_URL}"; then
    echo "Telegram downloaded. Extracting..."
    tar -xf tsetup.tar.xz
    if [ -d "Telegram" ]; then
        mkdir -p "${TELEGRAM_DIR}"
        mv Telegram/* "${TELEGRAM_DIR}/"
        # Create a symlink for easier execution if needed, or rely on .desktop file
        ln -sf "${TELEGRAM_DIR}/Telegram" /usr/local/bin/telegram-desktop

        # Create .desktop file for application menu
        # Icon path might need adjustment or download one if not included appropriately
        cat << EOF_TELEGRAM > "${TELEGRAM_DESKTOP_FILE}"
[Desktop Entry]
Version=1.0
Name=Telegram Desktop
Comment=Official Telegram Desktop client
Exec=/usr/local/bin/telegram-desktop
Icon=${TELEGRAM_DIR}/icon.png
Terminal=false
Type=Application
Categories=Network;InstantMessaging;Qt;
Keywords=tg;chat;im;messaging;messenger;sms;text;video;voice;call;
EOF_TELEGRAM
        # Try to find an icon, or use a generic one
        if [ ! -f "${TELEGRAM_DIR}/icon.png" ]; then
            # Attempt to find any .png in the Telegram dir to use as an icon
            FIRST_PNG=$(find "${TELEGRAM_DIR}" -name "*.png" -print -quit)
            if [ -n "$FIRST_PNG" ]; then
                sed -i "s|Icon=${TELEGRAM_DIR}/icon.png|Icon=${FIRST_PNG}|" "${TELEGRAM_DESKTOP_FILE}"
            else
                 sed -i "s|Icon=${TELEGRAM_DIR}/icon.png|Icon=telegram|" "${TELEGRAM_DESKTOP_FILE}" # Fallback to system icon name
            fi
        fi
        chmod +x /usr/local/bin/telegram-desktop
        echo "Telegram installed to ${TELEGRAM_DIR}."
        # Update desktop database for the .desktop file to be recognized
        update-desktop-database -q || echo "update-desktop-database failed, continuing..."
    else
        echo "Telegram directory not found after extraction."
    fi
    cd /
    rm -rf /tmp/telegram_install
else
    echo "Failed to download Telegram."
fi

# --- Finalization ---
# Create a flag file to indicate completion for the host script
SETUP_FLAG_FILE="/home/vmuser/vm_setup_complete.flag"
touch "${SETUP_FLAG_FILE}"
chown vmuser:vmuser "${SETUP_FLAG_FILE}"
echo "VM Guest setup script completed at $(date). Flag file created: ${SETUP_FLAG_FILE}"

# Optional: Clean up apt cache
apt-get clean

# Optional: sync filesystem
sync

echo "Setup script finished. VM should be ready."
exit 0

EOF
