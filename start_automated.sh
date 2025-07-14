#!/bin/bash

# Automated VM Manager Launcher
# Zero manual intervention required!

set -e

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

echo "🚀 === Fully Automated VM Manager ==="
echo "Zero manual intervention required!"
echo ""

# Function to check port availability
check_ports() {
    echo "🔍 Checking port availability..."
    local ports_in_use=()
    for port in {5900..5909}; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            ports_in_use+=($port)
        fi
    done
    
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        echo "❌ ERROR: The following VNC ports are in use: ${ports_in_use[*]}"
        echo "Run cleanup first: sudo ./complete_cleanup.sh"
        return 1
    fi
    echo "✅ All VNC ports (5900-5909) are available."
    return 0
}

# Function to check disk space
check_disk_space() {
    echo "💾 Checking disk space..."
    local available_gb=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    local required_gb=250  # 10 VMs * 20GB each + overhead
    
    if [ $available_gb -lt $required_gb ]; then
        echo "⚠️  WARNING: Available disk space: ${available_gb}GB, Required: ${required_gb}GB"
        echo "You may run out of disk space during VM creation."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting."
            exit 1
        fi
    else
        echo "✅ Disk space OK: ${available_gb}GB available (${required_gb}GB required)"
    fi
}

# Function to check KVM
check_kvm() {
    echo "🔧 Checking KVM availability..."
    if command -v kvm-ok > /dev/null 2>&1; then
        if kvm-ok > /dev/null 2>&1; then
            echo "✅ KVM is available and working"
        else
            echo "❌ ERROR: KVM is not available"
            echo "Please enable virtualization in BIOS and ensure KVM modules are loaded"
            return 1
        fi
    else
        echo "⚠️  WARNING: kvm-ok command not found"
        echo "Proceeding anyway..."
    fi
    return 0
}

# Pre-flight checks
echo "🔍 === Pre-flight Checks ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run with sudo: sudo $0"
    exit 1
fi

# Check KVM
if ! check_kvm; then
    exit 1
fi

# Check ports
if ! check_ports; then
    exit 1
fi

# Check disk space
check_disk_space

echo ""
echo "🎯 === Ready for Automated VM Creation ==="
echo ""
echo "This will create 10 Ubuntu Desktop VMs with:"
echo "✅ Fully automated installation (no manual steps)"
echo "✅ Ubuntu 22.04 Desktop with GNOME"
echo "✅ VNC remote access (ports 5900-5909)"
echo "✅ OpenVPN client with unique configurations"
echo "✅ Telegram Desktop pre-installed"
echo "✅ SSH access enabled"
echo "✅ User: vmuser / Password: userpass"
echo ""
echo "📊 Resource Usage:"
echo "   Disk: ~200GB total"
echo "   RAM: ~20GB total"  
echo "   Time: 10-15 minutes per VM"
echo ""
echo "🔐 Network Access:"
echo "   VNC: localhost:5900-5909"
echo "   SSH: VM internal IPs"
echo "   Internet: Via OpenVPN"
echo ""

read -p "🚀 Start automated VM creation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborting."
    exit 1
fi

echo ""
echo "🚀 === Starting Automated VM Creation ==="
echo "⏰ Started at: $(date)"
echo ""
echo "📝 What's happening:"
echo "1. Downloading Ubuntu Cloud Image (if needed)"
echo "2. Creating VM configurations"  
echo "3. Starting automated installations"
echo "4. Cloud-init will handle everything automatically"
echo ""
echo "💡 You can monitor progress with:"
echo "   ./monitor_progress.sh (in another terminal)"
echo ""
echo "🎮 VNC will be available after installation:"
echo "   VM1: localhost:5900"
echo "   VM2: localhost:5901"
echo "   ... and so on"
echo ""

# Start the automated creation
exec ./manage_vms_automated.sh "$@"