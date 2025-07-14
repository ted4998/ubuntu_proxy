# QEMU VM Manager - Complete Guide for 10 VMs (Scalable to 20 VMs)

## Overview
This enhanced QEMU VM Manager can create and manage 10 Ubuntu Desktop VMs with unique configurations, VPN connections, and VNC access. It's designed to easily scale to 20 VMs when needed.

## Quick Start

### 1. Clean Up Previous Runs
```bash
sudo ./complete_cleanup.sh
```

### 2. Validate System
```bash
./validate_system.sh
```

### 3. Start VM Creation (Recommended)
```bash
sudo ./start_10_vms.sh
```

### 4. Monitor Progress (In Another Terminal)
```bash
./monitor_progress.sh
```

## Manual Commands

### Start VMs Manually
```bash
# Test mode (validation only)
sudo ./manage_vms.sh --test-mode

# Create all 10 VMs
sudo ./manage_vms.sh

# Skip KVM check (for testing)
sudo ./manage_vms.sh --skip-kvm-check
```

### Check Status
```bash
./check_status.sh
```

### Complete Cleanup
```bash
sudo ./complete_cleanup.sh
```

## VM Specifications

### Each VM Gets:
- **OS**: Ubuntu 22.04.4 Desktop (Minimal)
- **RAM**: ~2GB (with slight variations)
- **Disk**: 20GB
- **CPU**: 1 core with 80% limit
- **VNC Port**: 5900-5909 (localhost:5900 for VM1, localhost:5901 for VM2, etc.)
- **Unique**: MAC address, UUID, BIOS serial, CPU model
- **VPN**: Unique OpenVPN configuration
- **Software**: VNC server, OpenVPN client, Telegram Desktop

### Network Access:
- **VNC**: Connect to `localhost:5900` through `localhost:5909`
- **Credentials**: Username `vmuser`, Password `userpass`
- **VNC Passwords**: Unique per VM (see `output/vm_info.txt`)

## Resource Requirements

### Minimum System Requirements:
- **CPU**: 4+ cores (recommended 8+ for good performance)
- **RAM**: 32GB+ (10 VMs × 2GB each + host overhead)
- **Disk**: 250GB+ free space (10 VMs × 20GB each + overhead)
- **Architecture**: x86_64
- **Virtualization**: KVM enabled

### Port Usage:
- **VNC**: 5900-5909 (10 ports)
- **HTTP Servers**: 8000-8009 (temporary during installation)
- **QEMU Monitor**: 4401-4410
- **QMP**: 4501-4510

## File Structure

```
/your/project/directory/
├── manage_vms.sh              # Main VM creation script
├── start_20_vms.sh           # Enhanced startup with checks
├── complete_cleanup.sh       # Complete system cleanup
├── validate_system.sh        # System validation
├── check_status.sh           # Status checker
├── monitor_progress.sh       # Progress monitor
├── cleanup_vm_environment.sh # Standard cleanup
├── bootstrap_vm_setup.sh     # Bootstrap script
├── scripts/
│   ├── generate_vm_configs.py # VM configuration generator
│   ├── preseed.cfg           # Ubuntu installation automation
│   └── setup_vm_in_guest.sh  # In-guest setup script
├── vpn/
│   ├── vpn-1.ovpn           # VPN configs 1-20
│   └── ... (vpn-20.ovpn)
├── vm_configs/              # Generated VM configurations
├── vm_disks/               # VM disk images
└── output/
    └── vm_info.txt         # VM access information
```

## Usage Scenarios

### Development/Testing
```bash
# Validate configuration only
sudo ./manage_vms.sh --test-mode

# Create just a few VMs for testing
# (Edit NUM_VMS in manage_vms.sh temporarily)
```

### Production Deployment
```bash
# Full 20 VM deployment
sudo ./start_20_vms.sh
```

### Maintenance
```bash
# Check current status
./check_status.sh

# Monitor ongoing creation
./monitor_progress.sh

# Clean everything
sudo ./complete_cleanup.sh
```

## Troubleshooting

### Common Issues:

1. **Port Already in Use**
   ```bash
   sudo ./complete_cleanup.sh
   ```

2. **Out of Disk Space**
   - Check: `df -h`
   - Free space or reduce VM count

3. **KVM Not Available**
   - Enable virtualization in BIOS
   - Load KVM modules: `sudo modprobe kvm`

4. **HTTP Server Failures**
   - Clean up: `sudo pkill -f "python.*http.server"`
   - Check ports: `netstat -tuln | grep 800`

5. **VM Creation Stalled**
   - Check logs in terminal output
   - Monitor with `./monitor_progress.sh`
   - Check individual VM via VNC

### Log Files:
- **Main output**: Terminal where you ran the script
- **VM info**: `output/vm_info.txt`
- **Individual VM logs**: Available via VNC connection to each VM

## Performance Tips

1. **Create VMs in batches**: Consider modifying NUM_VMS to create 5-10 VMs at a time
2. **SSD recommended**: Much faster VM creation and operation
3. **Monitor resources**: Use `htop`, `iotop` to monitor system load
4. **Network bandwidth**: VPN connections will use network bandwidth

## Security Notes

- Default password is `userpass` (change after creation)
- VNC passwords are in `output/vm_info.txt`
- VMs have internet access via VPN
- Consider firewall rules for production use

## Advanced Configuration

### Modify VM Specifications:
Edit `scripts/generate_vm_configs.py`:
- Change RAM allocation
- Modify CPU models
- Adjust disk sizes

### Custom VPN Configurations:
Replace files in `vpn/` directory with your own OpenVPN configs

### Change VM Count:
Modify `NUM_VMS=20` in:
- `manage_vms.sh`
- `scripts/generate_vm_configs.py`
- `validate_system.sh`
- `cleanup_vm_environment.sh`

## Support

If you encounter issues:
1. Run `./validate_system.sh`
2. Check `./check_status.sh`
3. Review terminal output for error messages
4. Use `./complete_cleanup.sh` to reset

---

**Total Creation Time**: Expect 2-6 hours depending on your hardware and internet connection.
**Final Result**: 20 fully functional Ubuntu Desktop VMs with VPN and remote access.