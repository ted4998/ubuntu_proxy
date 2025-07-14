#!/bin/bash

# VM Creation Progress Monitor
# This script monitors the progress of VM creation

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

echo "=== QEMU VM Manager - Progress Monitor ==="

while true; do
    clear
    echo "=== VM Creation Progress Monitor ==="
    echo "Time: $(date)"
    echo ""
    
    # Count created disk images
    disk_count=0
    if [ -d "vm_disks" ]; then
        disk_count=$(ls vm_disks/*.qcow2 2>/dev/null | wc -l)
    fi
    
    # Count running VMs
    vm_count=$(ps aux | grep -c "qemu-system-x86_64.*ubuntu-vm-" 2>/dev/null || echo "0")
    
    # Count HTTP servers
    http_count=$(ps aux | grep -c "python.*http.server.*800" 2>/dev/null || echo "0")
    
    # Check VNC ports
    vnc_active=0
    for port in {5900..5909}; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            ((vnc_active++))
        fi
    done
    
    echo "Progress Status:"
    echo "- Disk images created: $disk_count/10"
    echo "- VMs currently running: $vm_count/10"
    echo "- HTTP servers active: $http_count"
    echo "- VNC ports active: $vnc_active/10"
    echo ""
    
    # Show recent log entries
    if [ -f "output/vm_info.txt" ]; then
        echo "Latest VM Info:"
        tail -n 5 "output/vm_info.txt" 2>/dev/null || echo "No VM info yet"
    else
        echo "No VM info file yet"
    fi
    
    echo ""
    echo "Active HTTP Servers:"
    ps aux | grep "python.*http.server" | grep -v grep | head -5
    
    echo ""
    echo "Press Ctrl+C to exit monitor"
    echo "Refreshing in 10 seconds..."
    
    sleep 10
done