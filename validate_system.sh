#!/bin/bash

# Validation script to check the VM manager system without running VMs
# This can be used to validate the configuration in any environment

set -e

PROJECT_DIR_REALPATH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VPN_CONFIG_DIR="${PROJECT_DIR_REALPATH}/vpn"
VM_CONFIGS_DIR="${PROJECT_DIR_REALPATH}/vm_configs"
SCRIPTS_DIR="${PROJECT_DIR_REALPATH}/scripts"
NUM_VMS=10

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

validate_files() {
    log "=== Validating Project Files ==="
    
    local files_valid=true
    
    # Check main scripts
    if [ -f "${PROJECT_DIR_REALPATH}/manage_vms.sh" ] && [ -x "${PROJECT_DIR_REALPATH}/manage_vms.sh" ]; then
        success "manage_vms.sh exists and is executable"
    else
        error "manage_vms.sh missing or not executable"
        files_valid=false
    fi
    
    if [ -f "${PROJECT_DIR_REALPATH}/cleanup_vm_environment.sh" ] && [ -x "${PROJECT_DIR_REALPATH}/cleanup_vm_environment.sh" ]; then
        success "cleanup_vm_environment.sh exists and is executable"
    else
        error "cleanup_vm_environment.sh missing or not executable"
        files_valid=false
    fi
    
    if [ -f "${PROJECT_DIR_REALPATH}/bootstrap_vm_setup.sh" ] && [ -x "${PROJECT_DIR_REALPATH}/bootstrap_vm_setup.sh" ]; then
        success "bootstrap_vm_setup.sh exists and is executable"
    else
        error "bootstrap_vm_setup.sh missing or not executable"
        files_valid=false
    fi
    
    # Check scripts directory
    if [ -f "${SCRIPTS_DIR}/generate_vm_configs.py" ] && [ -x "${SCRIPTS_DIR}/generate_vm_configs.py" ]; then
        success "generate_vm_configs.py exists and is executable"
    else
        error "generate_vm_configs.py missing or not executable"
        files_valid=false
    fi
    
    if [ -f "${SCRIPTS_DIR}/preseed.cfg" ]; then
        success "preseed.cfg exists"
    else
        error "preseed.cfg missing"
        files_valid=false
    fi
    
    if [ -f "${SCRIPTS_DIR}/setup_vm_in_guest.sh" ] && [ -x "${SCRIPTS_DIR}/setup_vm_in_guest.sh" ]; then
        success "setup_vm_in_guest.sh exists and is executable"
    else
        error "setup_vm_in_guest.sh missing or not executable"
        files_valid=false
    fi
    
    return $files_valid
}

validate_vpn_configs() {
    log "=== Validating VPN Configurations ==="
    
    local vpn_valid=true
    
    if [ ! -d "$VPN_CONFIG_DIR" ]; then
        error "VPN config directory $VPN_CONFIG_DIR not found"
        return 1
    fi
    
    for i in $(seq 1 "$NUM_VMS"); do
        local vpn_file="${VPN_CONFIG_DIR}/vpn-${i}.ovpn"
        if [ -f "$vpn_file" ]; then
            # Check if it's a valid OpenVPN config (contains 'client' directive)
            if grep -q "^client" "$vpn_file"; then
                success "VPN config vpn-${i}.ovpn is valid"
            else
                warning "VPN config vpn-${i}.ovpn may be invalid (no 'client' directive found)"
            fi
        else
            error "VPN config file vpn-${i}.ovpn not found"
            vpn_valid=false
        fi
    done
    
    return $vpn_valid
}

validate_vm_configs() {
    log "=== Validating VM Configurations ==="
    
    # Generate VM configurations
    log "Generating VM configurations..."
    if python3 "${SCRIPTS_DIR}/generate_vm_configs.py"; then
        success "VM configurations generated successfully"
    else
        error "Failed to generate VM configurations"
        return 1
    fi
    
    # Validate generated configurations
    local configs_valid=true
    
    for i in $(seq 1 "$NUM_VMS"); do
        local config_file="${VM_CONFIGS_DIR}/vm-${i}.json"
        if [ -f "$config_file" ]; then
            # Check if it's valid JSON
            if jq empty "$config_file" > /dev/null 2>&1; then
                success "VM config vm-${i}.json is valid JSON"
                
                # Check required fields
                local required_fields=("vm_id" "vm_name" "mac_address" "vnc_port_host" "vnc_password" "uuid" "bios_serial" "cpu_model" "ram_size_mb" "disk_size_gb" "openvpn_config_file")
                
                for field in "${required_fields[@]}"; do
                    if jq -e ".$field" "$config_file" > /dev/null 2>&1; then
                        success "  VM config vm-${i}.json has required field: $field"
                    else
                        error "  VM config vm-${i}.json missing required field: $field"
                        configs_valid=false
                    fi
                done
            else
                error "VM config vm-${i}.json is not valid JSON"
                configs_valid=false
            fi
        else
            error "VM config file vm-${i}.json not found"
            configs_valid=false
        fi
    done
    
    return $configs_valid
}

validate_system_requirements() {
    log "=== Validating System Requirements ==="
    
    local sys_valid=true
    
    # Check architecture
    local arch=$(uname -m)
    if [ "$arch" = "x86_64" ]; then
        success "System architecture is x86_64"
    else
        warning "System architecture is $arch (expected x86_64)"
    fi
    
    # Check if running in container
    if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q "container" /proc/1/cgroup 2>/dev/null; then
        warning "Running in container environment - KVM may not be available"
    else
        success "Not running in container environment"
    fi
    
    # Check required commands
    local required_commands=("python3" "jq" "wget" "qemu-system-x86_64" "qemu-img" "cpulimit")
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" > /dev/null 2>&1; then
            success "Required command '$cmd' is available"
        else
            error "Required command '$cmd' is not available"
            sys_valid=false
        fi
    done
    
    # Check KVM availability
    if command -v kvm-ok > /dev/null 2>&1; then
        if kvm-ok > /dev/null 2>&1; then
            success "KVM is available and working"
        else
            warning "KVM is not available or not working properly"
        fi
    else
        warning "kvm-ok command not found - cannot check KVM availability"
    fi
    
    return $sys_valid
}

main() {
    log "Starting VM Manager System Validation"
    log "Project directory: $PROJECT_DIR_REALPATH"
    
    local overall_valid=true
    
    if ! validate_files; then
        overall_valid=false
    fi
    
    if ! validate_vpn_configs; then
        overall_valid=false
    fi
    
    if ! validate_vm_configs; then
        overall_valid=false
    fi
    
    if ! validate_system_requirements; then
        overall_valid=false
    fi
    
    log "=== Validation Summary ==="
    if [ "$overall_valid" = true ]; then
        success "All validations passed! System appears to be ready."
        log "You can now run './manage_vms.sh' to create VMs (requires KVM support)"
        log "Or run './manage_vms.sh --test-mode' to test without creating actual VMs"
    else
        error "Some validations failed. Please address the issues above."
        log "You can still run './manage_vms.sh --test-mode' to test configuration validation"
    fi
}

# Run main function
main "$@"