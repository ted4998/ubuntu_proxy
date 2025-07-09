import json
import uuid
import random
import os

def generate_mac_address():
    """Generates a random MAC address for QEMU."""
    # QEMU's OUI is 52:54:00, rest can be random
    mac = [0x52, 0x54, 0x00,
           random.randint(0x00, 0x7f),
           random.randint(0x00, 0xff),
           random.randint(0x00, 0xff)]
    return ':'.join(map(lambda x: "%02x" % x, mac))

def generate_bios_serial(vm_id):
    """Generates a unique BIOS serial number for a VM."""
    return f"VMBS{vm_id:04d}RND{random.randint(1000,9999)}"

def generate_vnc_password(length=8):
    """Generates a random alphanumeric VNC password."""
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join(random.choice(chars) for _ in range(length))

# List of CPU models for QEMU. This provides some variation.
# Sourced from `qemu-system-x86_64 -cpu help`
CPU_MODELS = [
    "Nehalem-IBRS", "Westmere-IBRS", "SandyBridge-IBRS", "IvyBridge-IBRS",
    "Haswell-noTSX-IBRS", "Broadwell-noTSX-IBRS", "Skylake-Client-IBRS",
    "Cascadelake-Server-noTSX", "EPYC-IBPB", "EPYC-Rome", "EPYC-Milan",
    "athlon", "phenom", "Opteron_G1", "Opteron_G2", "Opteron_G3", "Opteron_G4", "Opteron_G5",
    "kvm64", "qemu64", "max" # 'max' can be good for variety but might be too host-like
]

# Ensure enough unique CPU models, or repeat them if fewer than NUM_VMS
NUM_VMS = 10
if len(CPU_MODELS) < NUM_VMS:
    cpu_model_choices = CPU_MODELS * (NUM_VMS // len(CPU_MODELS)) + CPU_MODELS[:NUM_VMS % len(CPU_MODELS)]
else:
    cpu_model_choices = random.sample(CPU_MODELS, NUM_VMS)


def main():
    # Output directory should be relative to the project root,
    # assuming the script is run from the project root.
    # The CWD of run_in_bash_session (where python3 is called) is /app/qemu_vm_manager/
    # The script is in /app/qemu_vm_manager/scripts/
    # We want output in /app/qemu_vm_manager/vm_configs/
    # So, relative to the CWD of run_in_bash_session, output_dir should be "vm_configs/"
    output_dir = "vm_configs"
    # script_dir = os.path.dirname(os.path.abspath(__file__)) # /app/qemu_vm_manager/scripts
    # project_root = os.path.dirname(script_dir) # /app/qemu_vm_manager
    # output_dir = os.path.join(project_root, "vm_configs") # This would be more robust
    # output_dir = os.path.join(script_dir, "../vm_configs")
    os.makedirs(output_dir, exist_ok=True)

    all_vm_details = []

    for i in range(1, NUM_VMS + 1):
        vm_id = i
        vm_name = f"ubuntu-vm-{vm_id}"

        # Ensure RAM size is slightly different for some VMs for fingerprinting
        # For example, 7 VMs get 2048MB, 3 VMs get a slightly different value.
        if i % 4 == 0: # About 1/4 of VMs get a slightly different RAM
            ram_mb = random.choice([2000, 2096, 2144])
        else:
            ram_mb = 2048

        vm_config = {
            "vm_id": vm_id,
            "vm_name": vm_name,
            "mac_address": generate_mac_address(),
            "vnc_port_host": 5900 + (vm_id - 1),
            "vnc_password": generate_vnc_password(),
            "uuid": str(uuid.uuid4()),
            "bios_serial": generate_bios_serial(vm_id),
            "cpu_model": cpu_model_choices[vm_id - 1], # Assign a pre-selected unique CPU model
            "ram_size_mb": ram_mb,
            "disk_size_gb": 20, # Can also vary this slightly if desired
            "openvpn_config_file": f"vpn-{vm_id}.ovpn",
        }

        config_filepath = os.path.join(output_dir, f"vm-{vm_id}.json")
        with open(config_filepath, 'w') as f:
            json.dump(vm_config, f, indent=4)

        print(f"Generated config for {vm_name} at {config_filepath}")

        # Storing details for the vm_info.txt (to be created by manage_vms.sh)
        # manage_vms.sh will read these JSONs to populate vm_info.txt
        all_vm_details.append({
            "vm_name": vm_config["vm_name"],
            "mac_address": vm_config["mac_address"],
            "vnc_port_host": vm_config["vnc_port_host"],
            "vnc_password": vm_config["vnc_password"],
            "uuid": vm_config["uuid"],
            "bios_serial": vm_config["bios_serial"]
        })

    # This script itself doesn't write to vm_info.txt directly
    # It just prepares the JSON files.
    # The main manage_vms.sh will be responsible for vm_info.txt
    print(f"\nSuccessfully generated {NUM_VMS} VM configuration files in {os.path.abspath(output_dir)}.")

if __name__ == "__main__":
    main()
