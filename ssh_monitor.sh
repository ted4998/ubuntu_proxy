#!/bin/bash

# SSH and System Health Monitor
# Monitors system resources and SSH health during VM creation

set -e

MONITOR_LOG="/tmp/ssh_monitor_$(date +%Y%m%d_%H%M%S).log"
ALERT_THRESHOLD_RAM=90
ALERT_THRESHOLD_LOAD=5.0
ALERT_THRESHOLD_SWAP=50

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_monitor() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MONITOR_LOG"
}

alert() {
    echo -e "${RED}[ALERT] $1${NC}" | tee -a "$MONITOR_LOG"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$MONITOR_LOG"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$MONITOR_LOG"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" | tee -a "$MONITOR_LOG"
}

get_memory_stats() {
    local mem_total=$(free | awk '/^Mem:/{print $2}')
    local mem_used=$(free | awk '/^Mem:/{print $3}')
    local mem_available=$(free | awk '/^Mem:/{print $7}')
    local mem_percent=$(( (mem_used * 100) / mem_total ))
    
    echo "$mem_percent $mem_used $mem_available $mem_total"
}

get_swap_stats() {
    local swap_total=$(free | awk '/^Swap:/{print $2}')
    local swap_used=$(free | awk '/^Swap:/{print $3}')
    local swap_percent=0
    
    if [ $swap_total -gt 0 ]; then
        swap_percent=$(( (swap_used * 100) / swap_total ))
    fi
    
    echo "$swap_percent $swap_used $swap_total"
}

get_load_average() {
    uptime | awk '{print $10}' | cut -d',' -f1
}

get_process_count() {
    ps aux | wc -l
}

check_ssh_health() {
    # Check SSH daemon
    if ! systemctl is-active --quiet ssh; then
        echo "SSH_DOWN"
        return 1
    fi
    
    # Check SSH port
    if ! netstat -tuln | grep -q ":22 "; then
        echo "SSH_NO_PORT"
        return 1
    fi
    
    # Check SSH connections
    local ssh_connections=$(ss -tuln | grep -c ":22 " || echo "0")
    echo "SSH_OK:$ssh_connections"
    return 0
}

check_oom_killer() {
    local oom_kills=$(dmesg | grep -i "killed process" | tail -1)
    if [ -n "$oom_kills" ]; then
        echo "OOM_KILL_DETECTED"
        return 1
    fi
    echo "OOM_OK"
    return 0
}

emergency_cleanup() {
    alert "EMERGENCY: System resources critical - performing cleanup"
    
    # Kill all QEMU processes
    alert "Killing all QEMU processes..."
    pkill -f qemu-system-x86_64 || true
    
    # Kill cpulimit processes
    pkill -f cpulimit || true
    
    # Clear system cache
    alert "Clearing system cache..."
    sync
    echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    # Stop unnecessary services temporarily
    alert "Stopping non-essential services..."
    systemctl stop snapd || true
    systemctl stop packagekit || true
    
    alert "Emergency cleanup completed"
}

monitor_system() {
    local duration=${1:-300}  # Default 5 minutes
    local interval=${2:-2}    # Default 2 seconds
    
    info "Starting system monitoring for ${duration}s (interval: ${interval}s)"
    info "Monitor log: $MONITOR_LOG"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + duration))
    local critical_alerts=0
    
    # Create header
    printf "%-20s %-10s %-10s %-10s %-10s %-10s %-10s %-15s\n" \
        "Time" "RAM%" "Swap%" "Load" "Processes" "SSH" "OOM" "VMs" | tee -a "$MONITOR_LOG"
    
    while [ $(date +%s) -lt $end_time ]; do
        local current_time=$(date '+%H:%M:%S')
        
        # Get system stats
        local mem_stats=($(get_memory_stats))
        local mem_percent=${mem_stats[0]}
        local mem_used=${mem_stats[1]}
        local mem_available=${mem_stats[2]}
        local mem_total=${mem_stats[3]}
        
        local swap_stats=($(get_swap_stats))
        local swap_percent=${swap_stats[0]}
        local swap_used=${swap_stats[1]}
        local swap_total=${swap_stats[2]}
        
        local load_avg=$(get_load_average)
        local process_count=$(get_process_count)
        local ssh_status=$(check_ssh_health)
        local oom_status=$(check_oom_killer)
        local vm_count=$(pgrep -f qemu-system-x86_64 | wc -l)
        
        # Display current stats
        printf "%-20s %-10d %-10d %-10s %-10d %-10s %-10s %-15d\n" \
            "$current_time" "$mem_percent" "$swap_percent" "$load_avg" \
            "$process_count" "$ssh_status" "$oom_status" "$vm_count"
        
        # Check for critical conditions
        local critical_condition=false
        
        if [ $mem_percent -gt $ALERT_THRESHOLD_RAM ]; then
            alert "CRITICAL: Memory usage at ${mem_percent}% (threshold: ${ALERT_THRESHOLD_RAM}%)"
            critical_condition=true
        fi
        
        if [ $swap_percent -gt $ALERT_THRESHOLD_SWAP ]; then
            alert "CRITICAL: Swap usage at ${swap_percent}% (threshold: ${ALERT_THRESHOLD_SWAP}%)"
            critical_condition=true
        fi
        
        if (( $(echo "$load_avg > $ALERT_THRESHOLD_LOAD" | bc -l 2>/dev/null || echo "0") )); then
            alert "CRITICAL: Load average at $load_avg (threshold: $ALERT_THRESHOLD_LOAD)"
            critical_condition=true
        fi
        
        if [[ "$ssh_status" == "SSH_DOWN" ]]; then
            alert "CRITICAL: SSH is down!"
            critical_condition=true
        fi
        
        if [[ "$oom_status" == "OOM_KILL_DETECTED" ]]; then
            alert "CRITICAL: OOM killer activated!"
            critical_condition=true
        fi
        
        if [ "$critical_condition" = true ]; then
            critical_alerts=$((critical_alerts + 1))
            
            if [ $critical_alerts -ge 3 ]; then
                alert "EMERGENCY: Multiple critical alerts - performing emergency cleanup"
                emergency_cleanup
                break
            fi
        fi
        
        sleep $interval
    done
    
    info "Monitoring completed"
    info "Total critical alerts: $critical_alerts"
    
    return $critical_alerts
}

test_vm_creation_impact() {
    info "Testing VM creation impact on system resources..."
    
    # Record baseline
    local baseline_mem=($(get_memory_stats))
    local baseline_load=$(get_load_average)
    
    info "Baseline - RAM: ${baseline_mem[0]}%, Load: $baseline_load"
    
    # Start monitoring in background
    monitor_system 600 1 &
    local monitor_pid=$!
    
    # Wait a bit for monitoring to start
    sleep 3
    
    # Start VM creation
    info "Starting VM creation process..."
    
    if [ -f "create_vms_safe.sh" ]; then
        ./create_vms_safe.sh --vms 3 --batch-size 1 || true
    else
        warning "Safe VM creation script not found"
    fi
    
    # Wait for monitoring to complete
    wait $monitor_pid
    local monitor_result=$?
    
    # Analyze results
    info "VM creation test completed"
    info "Monitor result: $monitor_result critical alerts"
    
    return $monitor_result
}

analyze_logs() {
    info "Analyzing system logs for SSH issues..."
    
    # Check system logs for SSH-related issues
    local ssh_errors=$(journalctl -u ssh --since "10 minutes ago" --no-pager | grep -i error | wc -l)
    local ssh_warnings=$(journalctl -u ssh --since "10 minutes ago" --no-pager | grep -i warning | wc -l)
    
    info "SSH service errors in last 10 minutes: $ssh_errors"
    info "SSH service warnings in last 10 minutes: $ssh_warnings"
    
    # Check for OOM killer activity
    local oom_kills=$(dmesg | grep -i "killed process" | tail -5)
    if [ -n "$oom_kills" ]; then
        warning "Recent OOM killer activity:"
        echo "$oom_kills" | tee -a "$MONITOR_LOG"
    fi
    
    # Check for memory pressure
    local memory_pressure=$(dmesg | grep -i "memory pressure" | tail -3)
    if [ -n "$memory_pressure" ]; then
        warning "Memory pressure detected:"
        echo "$memory_pressure" | tee -a "$MONITOR_LOG"
    fi
    
    # Check system load
    local high_load=$(uptime | awk '{print $10}' | cut -d',' -f1)
    if (( $(echo "$high_load > 3.0" | bc -l 2>/dev/null || echo "0") )); then
        warning "High system load detected: $high_load"
    fi
}

generate_recommendations() {
    info "=== RECOMMENDATIONS TO PREVENT SSH CRASHES ==="
    
    local total_ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    local available_ram_gb=$(free -g | awk '/^Mem:/{print $7}')
    
    info "Current system resources:"
    info "  Total RAM: ${total_ram_gb}GB"
    info "  Available RAM: ${available_ram_gb}GB"
    
    if [ $available_ram_gb -lt 20 ]; then
        alert "RECOMMENDATION 1: REDUCE VM COUNT"
        info "  Current available RAM: ${available_ram_gb}GB"
        info "  Recommended max VMs: $((available_ram_gb / 2))"
        info "  Command: ./create_vms_safe.sh --vms $((available_ram_gb / 2))"
    fi
    
    if [ $total_ram_gb -lt 32 ]; then
        alert "RECOMMENDATION 2: REDUCE VM RAM"
        info "  Edit scripts/generate_vm_configs.py"
        info "  Change RAM from 2048MB to 1024MB or 512MB"
        info "  Or use: ./create_vms_safe.sh --ram 1024"
    fi
    
    info "RECOMMENDATION 3: USE BATCH CREATION"
    info "  Create VMs in small batches with delays"
    info "  Command: ./create_vms_safe.sh --batch-size 2"
    
    info "RECOMMENDATION 4: ENABLE SWAP (if not already)"
    info "  sudo fallocate -l 4G /swapfile"
    info "  sudo chmod 600 /swapfile"
    info "  sudo mkswap /swapfile"
    info "  sudo swapon /swapfile"
    
    info "RECOMMENDATION 5: INCREASE SSH LIMITS"
    info "  Edit /etc/ssh/sshd_config:"
    info "    MaxStartups 30:30:100"
    info "    MaxSessions 30"
    info "  Then: sudo systemctl restart ssh"
    
    info "RECOMMENDATION 6: MONITOR DURING CREATION"
    info "  Run this script while creating VMs:"
    info "  ./ssh_monitor.sh &"
    info "  ./create_vms_safe.sh"
}

main() {
    case "${1:-monitor}" in
        "monitor")
            local duration=${2:-300}
            monitor_system $duration
            ;;
        "test")
            test_vm_creation_impact
            ;;
        "analyze")
            analyze_logs
            ;;
        "recommend")
            generate_recommendations
            ;;
        "emergency")
            emergency_cleanup
            ;;
        "help"|"--help")
            echo "SSH and System Health Monitor"
            echo ""
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  monitor [duration]  Monitor system for specified seconds (default: 300)"
            echo "  test               Test VM creation impact"
            echo "  analyze            Analyze system logs"
            echo "  recommend          Generate recommendations"
            echo "  emergency          Perform emergency cleanup"
            echo "  help               Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 monitor 600     Monitor for 10 minutes"
            echo "  $0 test            Test VM creation impact"
            echo "  $0 analyze         Check logs for issues"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Set up signal handlers
trap 'emergency_cleanup; exit 130' INT TERM

# Run main function
main "$@"