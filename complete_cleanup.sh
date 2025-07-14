#!/bin/bash

# Comprehensive cleanup script for QEMU VM Manager
# This script cleans up everything before starting fresh

set -e

echo "=== QEMU VM Manager - Complete Cleanup ==="

# Kill all existing QEMU VMs
echo "Stopping all QEMU VMs..."
sudo pkill -f "qemu-system-x86_64" 2>/dev/null || true

# Kill all HTTP servers
echo "Stopping all Python HTTP servers..."
sudo pkill -f "python.*http.server" 2>/dev/null || true

# Free up all ports 8000-8019 (for 20 VMs)
echo "Freeing up ports 8000-8019..."
for port in {8000..8019}; do
    sudo fuser -k ${port}/tcp 2>/dev/null || true
done

# Kill cpulimit processes
echo "Stopping cpulimit processes..."
sudo pkill -f "cpulimit" 2>/dev/null || true

# Clean up temporary directories
echo "Cleaning up temporary directories..."
sudo rm -rf /tmp/qemu_http_serve-*

# Clean up PID files
echo "Cleaning up PID files..."
sudo rm -f /var/run/ubuntu-vm-*.pid

# Clean up existing VM disks (optional - uncomment if you want to start fresh)
# echo "Removing existing VM disks..."
# rm -rf vm_disks/*

# Clean up existing VM configs (they'll be regenerated)
echo "Cleaning up old VM configs..."
rm -rf vm_configs/*

# Clean up old output
echo "Cleaning up old output..."
rm -rf output/*

echo "=== Cleanup Complete! ==="
echo "System is ready for VM creation."