#!/bin/bash

# Enhanced startup script for QEMU VM Manager with 10 VMs
# This script performs pre-checks and starts the VM creation process

set -e

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

echo "=== QEMU VM Manager - Enhanced Startup (10 VMs) ==="
echo "Project Directory: $PROJECT_DIR"

# Function to check port availability
check_ports() {
    echo "Checking port availability (8000-8009)..."
    local ports_in_use=()
    for port in {8000..8009}; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            ports_in_use+=($port)
        fi
    done
    
    if [ ${#ports_in_use[@]} -gt 0 ]; then
        echo "ERROR: The following ports are in use: ${ports_in_use[*]}"
        echo "Please run cleanup first: sudo ./complete_cleanup.sh"
        return 1
    fi
    echo "All required ports (8000-8009) are available."
    return 0
}

# Function to check disk space
check_disk_space() {
    echo "Checking disk space..."
    local available_gb=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    local required_gb=$((10 * 20 + 10))  # 10 VMs * 20GB each + 10GB overhead
    
    if [ $available_gb -lt $required_gb ]; then
        echo "WARNING: Available disk space: ${available_gb}GB, Required: ${required_gb}GB"
        echo "You may run out of disk space during VM creation."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborting."
            exit 1
        fi
    else
        echo "Disk space OK: ${available_gb}GB available (${required_gb}GB required)"
    fi
}

# Function to validate system
validate_system() {
    echo "Running system validation..."
    if ./validate_system.sh | grep -q "ERROR"; then
        echo "System validation found errors. Please fix them before continuing."
        echo "You can run: ./validate_system.sh"
        return 1
    fi
    echo "System validation passed."
    return 0
}

# Pre-flight checks
echo "=== Pre-flight Checks ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo: sudo $0"
    exit 1
fi

# Validate system
if ! validate_system; then
    exit 1
fi

# Check ports
if ! check_ports; then
    exit 1
fi

# Check disk space
check_disk_space

# Confirm with user
echo ""
echo "=== Ready to Create 10 VMs ==="
echo "This will:"
echo "- Create 10 Ubuntu Desktop VMs"
echo "- Each VM will have 20GB disk space"
echo "- Each VM will have unique VPN configuration"
echo "- Each VM will have VNC access on ports 5900-5909"
echo "- Total disk usage: ~200GB"
echo ""
read -p "Continue with VM creation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
fi

# Start VM creation
echo ""
echo "=== Starting VM Creation ==="
echo "Starting time: $(date)"
echo "This may take 1-3 hours to complete..."
echo ""

# Run the main script
exec ./manage_vms.sh "$@"