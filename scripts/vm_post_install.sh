#!/bin/bash

# VM Post-Installation Setup Script
# This script runs inside each VM to complete the setup

set -e

VM_ID=${1:-1}
HOST_IP=${2:-10.0.2.2}
VPN_CONFIG_NAME=${3:-"vpn-${VM_ID}.ovpn"}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/vm-setup.log
}

setup_vnc() {
    log "Setting up VNC server..."
    
    # Ensure VNC password directory exists
    mkdir -p /home/vmuser/.vnc
    
    # Set VNC password (default: vnc123)
    echo "vnc123" | vncpasswd -f > /home/vmuser/.vnc/passwd
    chmod 600 /home/vmuser/.vnc/passwd
    chown -R vmuser:vmuser /home/vmuser/.vnc
    
    # Create VNC xstartup script
    cat > /home/vmuser/.vnc/xstartup << 'EOF'
#!/bin/bash
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP="ubuntu:GNOME"
export XDG_SESSION_DESKTOP="ubuntu"
export XDG_SESSION_TYPE="x11"
export GNOME_SHELL_SESSION_MODE="ubuntu"
export DESKTOP_SESSION="ubuntu"
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Start window manager
/usr/bin/gnome-session &
EOF
    
    chmod +x /home/vmuser/.vnc/xstartup
    chown vmuser:vmuser /home/vmuser/.vnc/xstartup
    
    # Create systemd service for x11vnc
    cat > /etc/systemd/system/x11vnc.service << 'EOF'
[Unit]
Description=VNC Server for VM
After=graphical.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/x11vnc -forever -display :0 -rfbauth /home/vmuser/.vnc/passwd -rfbport 5900 -shared -bg
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF
    
    systemctl daemon-reload
    systemctl enable x11vnc.service
    systemctl start x11vnc.service
    
    log "VNC server configured and started"
}

setup_openvpn() {
    log "Setting up OpenVPN..."
    
    # Create OpenVPN directory
    mkdir -p /etc/openvpn/client
    
    # Download VPN config from host (assuming HTTP server is running)
    local vpn_url="http://${HOST_IP}:8000/vpn/${VPN_CONFIG_NAME}"
    
    if wget -q --spider "$vpn_url" 2>/dev/null; then
        log "Downloading VPN config from $vpn_url"
        wget -O "/etc/openvpn/client/${VPN_CONFIG_NAME}" "$vpn_url"
        
        # Create systemd service for OpenVPN
        cat > "/etc/systemd/system/openvpn-client@${VM_ID}.service" << EOF
[Unit]
Description=OpenVPN Client for VM ${VM_ID}
After=network.target

[Service]
Type=notify
ExecStart=/usr/sbin/openvpn --config /etc/openvpn/client/${VPN_CONFIG_NAME}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        systemctl enable "openvpn-client@${VM_ID}.service"
        systemctl start "openvpn-client@${VM_ID}.service"
        
        log "OpenVPN configured and started"
    else
        log "Warning: Could not download VPN config from $vpn_url"
        log "Creating placeholder VPN config"
        
        cat > "/etc/openvpn/client/${VPN_CONFIG_NAME}" << 'EOF'
# Placeholder VPN config
# Replace with actual OpenVPN configuration
client
dev tun
proto udp
remote your-vpn-server.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
verb 3
EOF
        log "Placeholder VPN config created"
    fi
}

setup_telegram() {
    log "Setting up Telegram Desktop..."
    
    # Install Telegram Desktop via snap (if not already installed)
    if ! snap list telegram-desktop > /dev/null 2>&1; then
        snap install telegram-desktop
    fi
    
    # Create desktop shortcut
    cat > /home/vmuser/Desktop/Telegram.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Telegram
Comment=Official desktop application for the Telegram messaging service
TryExec=telegram-desktop
Exec=telegram-desktop %u
Icon=telegram
StartupWMClass=TelegramDesktop
StartupNotify=true
MimeType=x-scheme-handler/tg;
Categories=Chat;Network;InstantMessaging;Qt;
Keywords=tg;chat;im;messaging;messenger;sms;tdesktop;
X-GNOME-UsesNotifications=true
EOF
    
    chmod +x /home/vmuser/Desktop/Telegram.desktop
    chown vmuser:vmuser /home/vmuser/Desktop/Telegram.desktop
    
    log "Telegram Desktop configured"
}

setup_desktop_environment() {
    log "Configuring desktop environment..."
    
    # Enable auto-login for vmuser
    cat > /etc/gdm3/custom.conf << 'EOF'
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=vmuser

[security]

[xdmcp]

[chooser]

[debug]
EOF
    
    # Configure GNOME settings for vmuser
    sudo -u vmuser dbus-launch gsettings set org.gnome.desktop.screensaver lock-enabled false
    sudo -u vmuser dbus-launch gsettings set org.gnome.desktop.session idle-delay 0
    sudo -u vmuser dbus-launch gsettings set org.gnome.desktop.lockdown disable-lock-screen true
    
    # Create welcome script on desktop
    cat > /home/vmuser/Desktop/VM-Info.txt << EOF
=== VM Information ===
VM ID: ${VM_ID}
Hostname: $(hostname)
IP Address: $(hostname -I | cut -d' ' -f1)
VNC Port: 5900
SSH User: vmuser
Password: userpass

=== Services Status ===
VNC Server: $(systemctl is-active x11vnc.service 2>/dev/null || echo "unknown")
OpenVPN: $(systemctl is-active openvpn-client@${VM_ID}.service 2>/dev/null || echo "unknown")
SSH: $(systemctl is-active ssh.service 2>/dev/null || echo "unknown")

=== Applications ===
- Firefox Web Browser
- Telegram Desktop
- Terminal
- File Manager

Setup completed at: $(date)
EOF
    
    chown vmuser:vmuser /home/vmuser/Desktop/VM-Info.txt
    
    log "Desktop environment configured"
}

install_additional_tools() {
    log "Installing additional tools..."
    
    # Update package list
    apt-get update -qq
    
    # Install useful tools
    apt-get install -y \
        htop \
        neofetch \
        curl \
        wget \
        git \
        nano \
        vim \
        net-tools \
        tree \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release
    
    # Install Chrome (optional)
    if [ ! -f /etc/apt/sources.list.d/google-chrome.list ]; then
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
        echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
        apt-get update -qq
        apt-get install -y google-chrome-stable
    fi
    
    log "Additional tools installed"
}

create_startup_info() {
    log "Creating startup information..."
    
    # Create info script that shows on login
    cat > /home/vmuser/.profile_vm_info << 'EOF'
#!/bin/bash
echo "=================================="
echo "🖥️  VM Setup Complete!"
echo "=================================="
echo "VM ID: $VM_ID"
echo "Hostname: $(hostname)"
echo "IP: $(hostname -I | cut -d' ' -f1)"
echo ""
echo "🔐 Credentials:"
echo "  User: vmuser"
echo "  Pass: userpass"
echo ""
echo "🌐 Services:"
echo "  VNC: localhost:5900"
echo "  SSH: $(hostname -I | cut -d' ' -f1):22"
echo ""
echo "📱 Applications:"
echo "  - Firefox Browser"
echo "  - Telegram Desktop"
echo "  - Terminal & Tools"
echo ""
echo "💡 VPN Status:"
systemctl status openvpn-client@* --no-pager -l | grep -E "(Active|Main PID)" || echo "  Not configured"
echo ""
echo "=================================="
EOF
    
    # Add to bash profile
    echo 'source ~/.profile_vm_info' >> /home/vmuser/.bashrc
    chown vmuser:vmuser /home/vmuser/.profile_vm_info /home/vmuser/.bashrc
    
    log "Startup information created"
}

main() {
    log "=== Starting VM Post-Installation Setup ==="
    log "VM ID: $VM_ID"
    log "Host IP: $HOST_IP"
    log "VPN Config: $VPN_CONFIG_NAME"
    
    # Wait for system to be fully ready
    sleep 30
    
    # Run setup functions
    setup_vnc
    setup_openvpn
    setup_telegram
    setup_desktop_environment
    install_additional_tools
    create_startup_info
    
    # Final system update
    apt-get autoremove -y
    apt-get autoclean
    
    log "=== VM Post-Installation Setup Complete ==="
    log "VM is ready for use!"
    
    # Restart services to ensure everything is working
    systemctl restart gdm3
    systemctl restart x11vnc.service
    
    log "All services restarted. VM setup finished!"
}

# Run main function
main "$@"