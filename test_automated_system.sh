#!/bin/bash

# Comprehensive Automated Testing Script
# Tests the entire automated VM creation process

set -e

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_RESULTS=()
TOTAL_TESTS=0
PASSED_TESTS=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

test_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $test_name"
        if [ -n "$details" ]; then
            echo -e "${YELLOW}   Details: $details${NC}"
        fi
    fi
    
    TEST_RESULTS+=("$result:$test_name:$details")
}

test_environment() {
    log "=== Testing Environment Setup ==="
    
    # Test 1: Check if running as root
    if [ "$EUID" -eq 0 ]; then
        test_result "Root privileges" "PASS"
    else
        test_result "Root privileges" "FAIL" "Script must be run with sudo"
    fi
    
    # Test 2: Check required commands
    local required_commands=("qemu-system-x86_64" "qemu-img" "python3" "jq" "wget" "cloud-localds")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" > /dev/null 2>&1; then
            test_result "Command: $cmd" "PASS"
        else
            test_result "Command: $cmd" "FAIL" "Command not found"
            missing_commands+=("$cmd")
        fi
    done
    
    # Test 3: Check KVM availability
    if command -v kvm-ok > /dev/null 2>&1; then
        if kvm-ok > /dev/null 2>&1; then
            test_result "KVM availability" "PASS"
        else
            test_result "KVM availability" "FAIL" "KVM not available or not enabled"
        fi
    else
        test_result "KVM availability" "FAIL" "kvm-ok command not found"
    fi
    
    # Test 4: Check disk space
    local available_gb=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    if [ $available_gb -gt 50 ]; then
        test_result "Disk space" "PASS" "${available_gb}GB available"
    else
        test_result "Disk space" "FAIL" "Only ${available_gb}GB available (need 50GB+)"
    fi
    
    # Test 5: Check port availability
    local ports_in_use=()
    for port in {5900..5909}; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            ports_in_use+=($port)
        fi
    done
    
    if [ ${#ports_in_use[@]} -eq 0 ]; then
        test_result "VNC ports availability" "PASS"
    else
        test_result "VNC ports availability" "FAIL" "Ports in use: ${ports_in_use[*]}"
    fi
}

test_configuration_generation() {
    log "=== Testing Configuration Generation ==="
    
    # Test 1: VM config generation
    if [ -f "scripts/generate_vm_configs.py" ]; then
        if python3 scripts/generate_vm_configs.py > /dev/null 2>&1; then
            test_result "VM config generation" "PASS"
        else
            test_result "VM config generation" "FAIL" "Python script failed"
        fi
    else
        test_result "VM config generation" "FAIL" "generate_vm_configs.py not found"
    fi
    
    # Test 2: Generated config validation
    local config_count=0
    if [ -d "vm_configs" ]; then
        config_count=$(ls vm_configs/vm-*.json 2>/dev/null | wc -l)
    fi
    
    if [ $config_count -eq 10 ]; then
        test_result "Config file count" "PASS" "10 configs generated"
    else
        test_result "Config file count" "FAIL" "Expected 10, got $config_count"
    fi
    
    # Test 3: Config file validation
    local valid_configs=0
    for i in {1..10}; do
        local config_file="vm_configs/vm-${i}.json"
        if [ -f "$config_file" ] && jq empty "$config_file" 2>/dev/null; then
            valid_configs=$((valid_configs + 1))
        fi
    done
    
    if [ $valid_configs -eq 10 ]; then
        test_result "Config JSON validity" "PASS" "All configs are valid JSON"
    else
        test_result "Config JSON validity" "FAIL" "Only $valid_configs/10 configs are valid"
    fi
    
    # Test 4: VPN config files
    local vpn_count=0
    if [ -d "vpn" ]; then
        vpn_count=$(ls vpn/vpn-*.ovpn 2>/dev/null | wc -l)
    fi
    
    if [ $vpn_count -ge 10 ]; then
        test_result "VPN config files" "PASS" "$vpn_count configs available"
    else
        test_result "VPN config files" "FAIL" "Only $vpn_count/10 VPN configs found"
    fi
}

test_cloud_image_download() {
    log "=== Testing Cloud Image Download ==="
    
    local cloud_image_url="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    
    # Test 1: Internet connectivity
    if wget -q --spider "$cloud_image_url" 2>/dev/null; then
        test_result "Internet connectivity" "PASS" "Cloud image URL reachable"
    else
        test_result "Internet connectivity" "FAIL" "Cannot reach cloud image URL"
    fi
    
    # Test 2: Download capability (just check headers)
    if wget -q --spider --server-response "$cloud_image_url" 2>&1 | grep -q "200 OK"; then
        test_result "Cloud image availability" "PASS" "Cloud image is downloadable"
    else
        test_result "Cloud image availability" "FAIL" "Cloud image not available for download"
    fi
}

test_vm_creation_simulation() {
    log "=== Testing VM Creation (Simulation) ==="
    
    # Test 1: Test mode execution
    if ./manage_vms_automated.sh --test-mode > /dev/null 2>&1; then
        test_result "Test mode execution" "PASS"
    else
        test_result "Test mode execution" "FAIL" "Test mode failed"
    fi
    
    # Test 2: Cloud-init config generation
    local cloud_init_configs=0
    if [ -d "vm_disks" ]; then
        cloud_init_configs=$(ls vm_disks/*-cloud-init.iso 2>/dev/null | wc -l)
    fi
    
    if [ $cloud_init_configs -gt 0 ]; then
        test_result "Cloud-init config generation" "PASS" "$cloud_init_configs configs created"
    else
        test_result "Cloud-init config generation" "FAIL" "No cloud-init configs generated"
    fi
}

test_monitoring_scripts() {
    log "=== Testing Monitoring Scripts ==="
    
    # Test 1: Standard monitor script
    if [ -f "monitor_progress.sh" ] && [ -x "monitor_progress.sh" ]; then
        test_result "Monitor script exists" "PASS"
    else
        test_result "Monitor script exists" "FAIL" "monitor_progress.sh not found or not executable"
    fi
    
    # Test 2: Automated monitor script  
    if [ -f "monitor_automated.sh" ] && [ -x "monitor_automated.sh" ]; then
        test_result "Automated monitor script exists" "PASS"
    else
        test_result "Automated monitor script exists" "FAIL" "monitor_automated.sh not found or not executable"
    fi
    
    # Test 3: Status check script
    if [ -f "check_status.sh" ] && [ -x "check_status.sh" ]; then
        test_result "Status check script exists" "PASS"
    else
        test_result "Status check script exists" "FAIL" "check_status.sh not found or not executable"
    fi
}

test_validation_scripts() {
    log "=== Testing Validation Scripts ==="
    
    # Test 1: Main validation script
    if ./validate_system.sh > /dev/null 2>&1; then
        test_result "System validation" "PASS"
    else
        test_result "System validation" "FAIL" "Validation script failed"
    fi
    
    # Test 2: Scaling script
    if [ -f "scale_vms.sh" ] && [ -x "scale_vms.sh" ]; then
        if ./scale_vms.sh status > /dev/null 2>&1; then
            test_result "Scaling script" "PASS"
        else
            test_result "Scaling script" "FAIL" "scale_vms.sh status failed"
        fi
    else
        test_result "Scaling script" "FAIL" "scale_vms.sh not found or not executable"
    fi
}

generate_test_report() {
    log "=== Test Report ==="
    echo ""
    echo "========================================"
    echo "    AUTOMATED VM SYSTEM TEST REPORT"
    echo "========================================"
    echo ""
    echo "Test Date: $(date)"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $((TOTAL_TESTS - PASSED_TESTS))"
    echo "Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"
    echo ""
    
    if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
        echo -e "${GREEN}✅ System is ready for automated VM creation!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Run: sudo ./start_automated.sh"
        echo "  2. Monitor: ./monitor_automated.sh"
        echo "  3. Connect via VNC to localhost:5900-5909"
    else
        echo -e "${RED}❌ SOME TESTS FAILED!${NC}"
        echo -e "${YELLOW}⚠️  Please fix the failed tests before proceeding.${NC}"
        echo ""
        echo "Failed tests:"
        for result in "${TEST_RESULTS[@]}"; do
            IFS=':' read -r status name details <<< "$result"
            if [ "$status" = "FAIL" ]; then
                echo -e "${RED}  • $name${NC}"
                if [ -n "$details" ]; then
                    echo -e "${YELLOW}    $details${NC}"
                fi
            fi
        done
    fi
    echo ""
    echo "========================================"
}

# Cleanup function
cleanup_test_files() {
    log "Cleaning up test files..."
    rm -rf vm_configs/* vm_disks/* output/* 2>/dev/null || true
    log "Test cleanup complete."
}

main() {
    echo -e "${BLUE}🧪 STARTING AUTOMATED VM SYSTEM TESTING${NC}"
    echo ""
    
    # Clean up any previous test files
    cleanup_test_files
    
    # Run all test suites
    test_environment
    test_configuration_generation
    test_cloud_image_download
    test_vm_creation_simulation
    test_monitoring_scripts
    test_validation_scripts
    
    # Generate final report
    generate_test_report
    
    # Return appropriate exit code
    if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"