#!/usr/bin/env python3
"""
Comprehensive test suite for QEMU VM Manager system
Tests all components including validation, configuration generation, and system functionality
"""

import os
import sys
import json
import subprocess
import tempfile
import shutil
from pathlib import Path
import time

class QEMUVMManagerTester:
    def __init__(self):
        self.project_dir = Path("/app")
        self.tests_run = 0
        self.tests_passed = 0
        self.test_results = []
        
    def log_test(self, name, success, message=""):
        """Log test result"""
        self.tests_run += 1
        if success:
            self.tests_passed += 1
            status = "✅ PASS"
        else:
            status = "❌ FAIL"
        
        result = f"{status} - {name}"
        if message:
            result += f": {message}"
        
        print(result)
        self.test_results.append((name, success, message))
        return success

    def run_command(self, cmd, cwd=None, timeout=60):
        """Run shell command and return result"""
        try:
            if cwd is None:
                cwd = self.project_dir
            
            result = subprocess.run(
                cmd, 
                shell=True, 
                cwd=cwd, 
                capture_output=True, 
                text=True, 
                timeout=timeout
            )
            return result.returncode == 0, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return False, "", f"Command timed out after {timeout}s"
        except Exception as e:
            return False, "", str(e)

    def test_file_permissions(self):
        """Test that all scripts have proper execute permissions"""
        scripts = [
            "validate_system.sh",
            "manage_vms.sh", 
            "cleanup_vm_environment.sh",
            "bootstrap_vm_setup.sh",
            "scripts/generate_vm_configs.py",
            "scripts/setup_vm_in_guest.sh"
        ]
        
        all_good = True
        for script in scripts:
            script_path = self.project_dir / script
            if script_path.exists() and os.access(script_path, os.X_OK):
                self.log_test(f"File permissions - {script}", True, "Executable")
            else:
                self.log_test(f"File permissions - {script}", False, "Not executable or missing")
                all_good = False
        
        return all_good

    def test_validation_script(self):
        """Test the validation script functionality"""
        success, stdout, stderr = self.run_command("./validate_system.sh")
        
        # Check for key success indicators in output
        success_indicators = [
            "manage_vms.sh exists and is executable",
            "VPN config vpn-1.ovpn is valid",
            "VM configurations generated successfully",
            "Required command 'python3' is available"
        ]
        
        indicators_found = sum(1 for indicator in success_indicators if indicator in stdout)
        
        return self.log_test(
            "Validation script execution", 
            indicators_found >= 3,
            f"Found {indicators_found}/4 success indicators"
        )

    def test_help_functionality(self):
        """Test help functionality of main script"""
        success, stdout, stderr = self.run_command("./manage_vms.sh --help")
        
        help_indicators = [
            "Usage:",
            "--test-mode",
            "--skip-kvm-check", 
            "--help"
        ]
        
        indicators_found = sum(1 for indicator in help_indicators if indicator in stdout)
        
        return self.log_test(
            "Help functionality",
            success and indicators_found >= 3,
            f"Help displayed correctly with {indicators_found}/4 expected options"
        )

    def test_test_mode(self):
        """Test the main script in test mode"""
        success, stdout, stderr = self.run_command("./manage_vms.sh --test-mode", timeout=120)
        
        test_mode_indicators = [
            "Test mode: Validating VM",
            "TEST MODE SUMMARY",
            "Configuration validation completed for 10 VMs",
            "All VM configurations appear to be valid"
        ]
        
        indicators_found = sum(1 for indicator in test_mode_indicators if indicator in stdout)
        
        return self.log_test(
            "Test mode execution",
            success and indicators_found >= 3,
            f"Test mode completed with {indicators_found}/4 expected indicators"
        )

    def test_error_handling(self):
        """Test error handling with invalid scenarios"""
        # Test invalid command line option
        success, stdout, stderr = self.run_command("./manage_vms.sh --invalid-option")
        
        error_handled = not success and ("Unknown option" in stderr or "Unknown option" in stdout)
        
        return self.log_test(
            "Error handling - invalid option",
            error_handled,
            "Invalid option properly rejected"
        )

    def test_vpn_configs(self):
        """Test VPN configuration files are readable and valid"""
        vpn_dir = self.project_dir / "vpn"
        all_good = True
        
        for i in range(1, 11):  # Test vpn-1.ovpn to vpn-10.ovpn
            vpn_file = vpn_dir / f"vpn-{i}.ovpn"
            if vpn_file.exists():
                try:
                    content = vpn_file.read_text()
                    # Check for basic OpenVPN config indicators
                    has_client = "client" in content
                    has_remote = "remote" in content
                    has_ca = "<ca>" in content
                    
                    if has_client and has_remote and has_ca:
                        self.log_test(f"VPN config vpn-{i}.ovpn", True, "Valid OpenVPN config")
                    else:
                        self.log_test(f"VPN config vpn-{i}.ovpn", False, "Missing required OpenVPN directives")
                        all_good = False
                except Exception as e:
                    self.log_test(f"VPN config vpn-{i}.ovpn", False, f"Read error: {e}")
                    all_good = False
            else:
                self.log_test(f"VPN config vpn-{i}.ovpn", False, "File not found")
                all_good = False
        
        return all_good

    def test_vm_configs_generation(self):
        """Test VM configuration generation and validation"""
        # First run the generation script
        success, stdout, stderr = self.run_command("python3 scripts/generate_vm_configs.py")
        
        if not success:
            return self.log_test("VM config generation", False, f"Generation failed: {stderr}")
        
        # Check generated configs
        vm_configs_dir = self.project_dir / "vm_configs"
        all_good = True
        
        required_fields = [
            "vm_id", "vm_name", "mac_address", "vnc_port_host", 
            "vnc_password", "uuid", "bios_serial", "cpu_model", 
            "ram_size_mb", "disk_size_gb", "openvpn_config_file"
        ]
        
        for i in range(1, 11):  # Test vm-1.json to vm-10.json
            config_file = vm_configs_dir / f"vm-{i}.json"
            if config_file.exists():
                try:
                    with open(config_file, 'r') as f:
                        config = json.load(f)
                    
                    missing_fields = [field for field in required_fields if field not in config]
                    
                    if not missing_fields:
                        # Validate some field types and values
                        valid_config = (
                            isinstance(config['vm_id'], int) and
                            isinstance(config['vnc_port_host'], int) and
                            config['vnc_port_host'] >= 5900 and
                            config['mac_address'].startswith('52:54:00:') and
                            len(config['uuid']) == 36  # UUID length
                        )
                        
                        if valid_config:
                            self.log_test(f"VM config vm-{i}.json", True, "Valid JSON with all required fields")
                        else:
                            self.log_test(f"VM config vm-{i}.json", False, "Invalid field values")
                            all_good = False
                    else:
                        self.log_test(f"VM config vm-{i}.json", False, f"Missing fields: {missing_fields}")
                        all_good = False
                        
                except json.JSONDecodeError as e:
                    self.log_test(f"VM config vm-{i}.json", False, f"Invalid JSON: {e}")
                    all_good = False
                except Exception as e:
                    self.log_test(f"VM config vm-{i}.json", False, f"Error: {e}")
                    all_good = False
            else:
                self.log_test(f"VM config vm-{i}.json", False, "File not found")
                all_good = False
        
        return all_good

    def test_output_files(self):
        """Test that output files are created correctly"""
        output_dir = self.project_dir / "output"
        vm_info_file = output_dir / "vm_info.txt"
        
        if vm_info_file.exists():
            try:
                content = vm_info_file.read_text()
                lines = content.strip().split('\n')
                
                # Should have header lines + 10 VM entries
                has_header = any("VM_Name,MAC_Address" in line for line in lines)
                vm_entries = [line for line in lines if not line.startswith('#') and line.strip()]
                
                if has_header and len(vm_entries) == 10:
                    # Check format of first VM entry
                    first_entry = vm_entries[0].split(',')
                    if len(first_entry) == 6:  # vm_name, mac, vnc_port, vnc_pass, uuid, bios_serial
                        return self.log_test("Output file vm_info.txt", True, f"Valid format with {len(vm_entries)} VM entries")
                    else:
                        return self.log_test("Output file vm_info.txt", False, f"Invalid entry format: {len(first_entry)} fields")
                else:
                    return self.log_test("Output file vm_info.txt", False, f"Invalid structure: header={has_header}, entries={len(vm_entries)}")
                    
            except Exception as e:
                return self.log_test("Output file vm_info.txt", False, f"Read error: {e}")
        else:
            return self.log_test("Output file vm_info.txt", False, "File not found")

    def test_container_environment_detection(self):
        """Test container environment detection"""
        # Test the detection logic used in the scripts
        success, stdout, stderr = self.run_command(
            'if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q "container" /proc/1/cgroup 2>/dev/null; then echo "CONTAINER"; else echo "NOT_CONTAINER"; fi'
        )
        
        if success:
            is_container = "CONTAINER" in stdout
            return self.log_test(
                "Container environment detection", 
                True, 
                f"Environment detected as: {'Container' if is_container else 'Not Container'}"
            )
        else:
            return self.log_test("Container environment detection", False, "Detection command failed")

    def test_system_requirements(self):
        """Test system requirements validation"""
        required_commands = ["python3", "jq", "wget", "qemu-system-x86_64", "qemu-img", "cpulimit"]
        all_good = True
        
        for cmd in required_commands:
            success, stdout, stderr = self.run_command(f"command -v {cmd}")
            if success:
                self.log_test(f"Required command '{cmd}'", True, "Available")
            else:
                self.log_test(f"Required command '{cmd}'", False, "Not available")
                all_good = False
        
        return all_good

    def test_architecture_detection(self):
        """Test architecture detection"""
        success, stdout, stderr = self.run_command("uname -m")
        
        if success:
            arch = stdout.strip()
            return self.log_test(
                "Architecture detection", 
                True, 
                f"Detected architecture: {arch}"
            )
        else:
            return self.log_test("Architecture detection", False, "Failed to detect architecture")

    def run_all_tests(self):
        """Run all tests"""
        print("🚀 Starting QEMU VM Manager System Tests")
        print("=" * 60)
        
        # Run all test methods
        test_methods = [
            self.test_file_permissions,
            self.test_validation_script,
            self.test_help_functionality,
            self.test_test_mode,
            self.test_error_handling,
            self.test_vpn_configs,
            self.test_vm_configs_generation,
            self.test_output_files,
            self.test_container_environment_detection,
            self.test_system_requirements,
            self.test_architecture_detection
        ]
        
        for test_method in test_methods:
            try:
                test_method()
            except Exception as e:
                self.log_test(test_method.__name__, False, f"Test exception: {e}")
            print()  # Add spacing between test groups
        
        # Print summary
        print("=" * 60)
        print(f"📊 TEST SUMMARY")
        print(f"Tests run: {self.tests_run}")
        print(f"Tests passed: {self.tests_passed}")
        print(f"Tests failed: {self.tests_run - self.tests_passed}")
        print(f"Success rate: {(self.tests_passed/self.tests_run)*100:.1f}%")
        
        if self.tests_passed == self.tests_run:
            print("🎉 ALL TESTS PASSED!")
            return 0
        else:
            print("⚠️  SOME TESTS FAILED")
            print("\nFailed tests:")
            for name, success, message in self.test_results:
                if not success:
                    print(f"  - {name}: {message}")
            return 1

def main():
    """Main test runner"""
    tester = QEMUVMManagerTester()
    return tester.run_all_tests()

if __name__ == "__main__":
    sys.exit(main())