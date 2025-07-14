#!/bin/bash

# QEMU VM Manager Status Check
# Comprehensive status check for all 20 VMs

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

echo "=== QEMU VM Manager Status Check ==="
echo "Time: $(date)"
echo ""

# Check overall system
echo "=== System Overview ==="
echo "Architecture: $(uname -m)"
echo "KVM Available: $(kvm-ok 2>/dev/null && echo "Yes" || echo "No")"
echo "Disk Space Available: $(df -h . | awk 'NR==2 {print $4}')"
echo ""

# Check VM configurations
echo "=== VM Configurations ==="
if [ -d "vm_configs" ]; then
    config_count=$(ls vm_configs/vm-*.json 2>/dev/null | wc -l)
    echo "VM config files: $config_count/10"
else
    echo "VM config directory not found"
fi

# Check VPN configurations
echo ""
echo "=== VPN Configurations ==="
if [ -d "vpn" ]; then
    vpn_count=$(ls vpn/vpn-*.ovpn 2>/dev/null | wc -l)
    echo "VPN config files: $vpn_count/10 (available: $vpn_count)"
else
    echo "VPN directory not found"
fi

# Check disk images
echo ""
echo "=== VM Disk Images ==="
if [ -d "vm_disks" ]; then
    disk_count=$(ls vm_disks/*.qcow2 2>/dev/null | wc -l)
    echo "Disk images created: $disk_count/10"
    if [ $disk_count -gt 0 ]; then
        echo "Total disk usage: $(du -sh vm_disks/ 2>/dev/null | cut -f1)"
    fi
else
    echo "VM disks directory not found"
fi

# Check running VMs
echo ""
echo "=== Running VMs ==="
vm_pids=($(ps aux | grep "qemu-system-x86_64.*ubuntu-vm-" | grep -v grep | awk '{print $2}'))
echo "Running VMs: ${#vm_pids[@]}/10"

if [ ${#vm_pids[@]} -gt 0 ]; then
    echo ""
    echo "VM Details:"
    for pid in "${vm_pids[@]}"; do
        vm_info=$(ps -p $pid -o args= | grep -o "ubuntu-vm-[0-9]*")
        echo "- $vm_info (PID: $pid)"
    done
fi

# Check VNC ports
echo ""
echo "=== VNC Access Points ==="
vnc_ports=()
for port in {5900..5909}; do
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        vnc_ports+=($port)
    fi
done
echo "VNC ports active: ${#vnc_ports[@]}/10"

if [ ${#vnc_ports[@]} -gt 0 ]; then
    echo "Active VNC ports: ${vnc_ports[*]}"
fi

# Check HTTP servers
echo ""
echo "=== HTTP Servers ==="
http_servers=($(ps aux | grep "python.*http.server.*800" | grep -v grep | awk '{print $2}'))
echo "HTTP servers running: ${#http_servers[@]}"

# Check output files
echo ""
echo "=== Output Files ==="
if [ -f "output/vm_info.txt" ]; then
    vm_entries=$(grep -c "ubuntu-vm-" "output/vm_info.txt" 2>/dev/null || echo "0")
    echo "VM entries in info file: $vm_entries/20"
else
    echo "VM info file not found"
fi

# Port usage summary
echo ""
echo "=== Port Usage Summary ==="
echo "VNC Ports (5900-5919): ${#vnc_ports[@]}/20 in use"
http_ports=()
for port in {8000..8019}; do
    if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
        http_ports+=($port)
    fi
done
echo "HTTP Ports (8000-8019): ${#http_ports[@]}/20 in use"

# Resource usage
echo ""
echo "=== Resource Usage ==="
total_mem=$(ps aux | grep "qemu-system-x86_64.*ubuntu-vm-" | grep -v grep | awk '{sum+=$6} END {print sum/1024}')
if [ -n "$total_mem" ]; then
    echo "Total VM memory usage: ${total_mem}MB"
fi

cpu_usage=$(ps aux | grep "qemu-system-x86_64.*ubuntu-vm-" | grep -v grep | awk '{sum+=$3} END {print sum}')
if [ -n "$cpu_usage" ]; then
    echo "Total VM CPU usage: ${cpu_usage}%"
fi

echo ""
echo "=== Status Check Complete ==="