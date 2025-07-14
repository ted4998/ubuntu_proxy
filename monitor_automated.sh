#!/bin/bash

# Enhanced Progress Monitor for Automated VMs
# Shows real-time installation progress

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                 🚀 AUTOMATED VM PROGRESS MONITOR               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${BLUE}⏰ Time: $(date)${NC}"
    echo ""
}

check_vm_installation_status() {
    local vm_name=$1
    local vnc_port=$2
    
    # Check if VM process is running
    if pgrep -f "qemu.*${vm_name}" > /dev/null; then
        # Check if VNC is responding (indicates desktop is ready)
        if timeout 2 bash -c "</dev/tcp/localhost/$vnc_port" 2>/dev/null; then
            echo -e "${GREEN}🖥️  READY${NC}"
        else
            echo -e "${YELLOW}⚙️  INSTALLING${NC}"
        fi
    else
        echo -e "${RED}❌ STOPPED${NC}"
    fi
}

check_cloud_init_progress() {
    local vm_name=$1
    local cloud_init_log="/tmp/${vm_name}-cloudinit.log"
    
    # Try to check cloud-init status (this would require SSH access)
    # For now, we'll estimate based on time and VNC availability
    if [ -f "/var/run/${vm_name}.pid" ]; then
        local pid=$(cat "/var/run/${vm_name}.pid" 2>/dev/null)
        if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
            local runtime=$(ps -o etime= -p "$pid" | tr -d ' ')
            echo "⏱️  Runtime: $runtime"
        else
            echo "❌ Process not found"
        fi
    else
        echo "❓ No PID file"
    fi
}

show_installation_phases() {
    echo -e "${PURPLE}📋 Installation Phases (each VM goes through these):${NC}"
    echo -e "   1. ${CYAN}VM Startup${NC} (30s) - QEMU starts, cloud-init begins"
    echo -e "   2. ${YELLOW}Base Install${NC} (3-5 min) - Ubuntu system installation"
    echo -e "   3. ${BLUE}Desktop Install${NC} (3-5 min) - GNOME desktop packages"
    echo -e "   4. ${GREEN}Services Setup${NC} (2-3 min) - VNC, SSH, networking"
    echo -e "   5. ${PURPLE}Apps Install${NC} (2-3 min) - Telegram, OpenVPN, tools"
    echo -e "   6. ${GREEN}Ready${NC} - VNC accessible, all services running"
    echo ""
}

main_loop() {
    while true; do
        show_header
        
        # Count VMs
        local total_vms=0
        local running_vms=0
        local ready_vms=0
        
        if [ -d "vm_configs" ]; then
            total_vms=$(ls vm_configs/vm-*.json 2>/dev/null | wc -l)
        fi
        
        echo -e "${BLUE}📊 VM Status Overview:${NC}"
        echo "┌────────────────┬───────────────┬──────────────┬─────────────────┐"
        echo "│ VM Name        │ Status        │ VNC Port     │ Progress        │"
        echo "├────────────────┼───────────────┼──────────────┼─────────────────┤"
        
        for i in $(seq 1 "$total_vms"); do
            local vm_name="ubuntu-vm-$i"
            local vnc_port=$((5899 + i))
            local config_file="vm_configs/vm-${i}.json"
            
            if [ -f "$config_file" ]; then
                vnc_port=$(jq -r '.vnc_port_host' "$config_file" 2>/dev/null || echo $((5899 + i)))
            fi
            
            local status=$(check_vm_installation_status "$vm_name" "$vnc_port")
            local progress=$(check_cloud_init_progress "$vm_name")
            
            printf "│ %-14s │ %-13s │ %-12s │ %-15s │\n" "$vm_name" "$status" "$vnc_port" "$progress"
            
            # Count statuses
            if pgrep -f "qemu.*${vm_name}" > /dev/null; then
                ((running_vms++))
                if timeout 1 bash -c "</dev/tcp/localhost/$vnc_port" 2>/dev/null; then
                    ((ready_vms++))
                fi
            fi
        done
        
        echo "└────────────────┴───────────────┴──────────────┴─────────────────┘"
        echo ""
        
        # Summary
        echo -e "${BLUE}📈 Summary:${NC}"
        echo -e "   Total VMs: $total_vms"
        echo -e "   Running: ${YELLOW}$running_vms${NC}"
        echo -e "   Ready: ${GREEN}$ready_vms${NC}"
        echo -e "   Pending: ${CYAN}$((total_vms - running_vms))${NC}"
        echo ""
        
        # Resource usage
        echo -e "${BLUE}💻 Resource Usage:${NC}"
        local total_mem=$(ps aux | grep "qemu.*ubuntu-vm" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
        local cpu_usage=$(ps aux | grep "qemu.*ubuntu-vm" | grep -v grep | awk '{sum+=$3} END {print int(sum)}')
        echo -e "   Memory: ${total_mem:-0} MB"
        echo -e "   CPU: ${cpu_usage:-0}%"
        echo ""
        
        # Show installation phases
        show_installation_phases
        
        # VNC Connection Info
        if [ $ready_vms -gt 0 ]; then
            echo -e "${GREEN}🎮 Ready for VNC Connection:${NC}"
            for i in $(seq 1 "$total_vms"); do
                local vm_name="ubuntu-vm-$i"
                local vnc_port=$((5899 + i))
                local config_file="vm_configs/vm-${i}.json"
                
                if [ -f "$config_file" ]; then
                    vnc_port=$(jq -r '.vnc_port_host' "$config_file" 2>/dev/null || echo $((5899 + i)))
                    local vnc_password=$(jq -r '.vnc_password' "$config_file" 2>/dev/null || echo "unknown")
                fi
                
                if timeout 1 bash -c "</dev/tcp/localhost/$vnc_port" 2>/dev/null; then
                    echo -e "   ${GREEN}✅ $vm_name${NC}: localhost:$vnc_port (password: $vnc_password)"
                fi
            done
            echo ""
        fi
        
        # Tips
        echo -e "${CYAN}💡 Tips:${NC}"
        echo "   • Connect via VNC: Use TigerVNC, RealVNC, or built-in VNC client"
        echo "   • Login: vmuser / userpass"
        echo "   • SSH: ssh vmuser@<vm-ip> (check VM's IP via VNC)"
        echo "   • OpenVPN configs are in /etc/openvpn/client/ on each VM"
        echo ""
        echo -e "${YELLOW}Press Ctrl+C to exit monitor${NC}"
        echo -e "${BLUE}Refreshing in 10 seconds...${NC}"
        
        sleep 10
    done
}

# Trap Ctrl+C for clean exit
trap 'echo -e "\n${GREEN}Monitoring stopped.${NC}"; exit 0' INT

# Start monitoring
main_loop