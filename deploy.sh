#!/bin/bash

# Final Deployment Summary - Show All Available Options
# This script shows all the automation options available

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_DIR"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    🚀 AUTOMATED VM MANAGER - DEPLOYMENT READY               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✅ FULLY AUTOMATED SOLUTION - ZERO MANUAL INTERVENTION REQUIRED!${NC}"
    echo ""
}

show_options() {
    echo -e "${BLUE}🎯 CHOOSE YOUR DEPLOYMENT METHOD:${NC}"
    echo ""
    
    echo -e "${GREEN}1. 🚀 FULLY AUTOMATED (Recommended)${NC}"
    echo "   • Zero manual steps required"
    echo "   • Uses Ubuntu Cloud Images"
    echo "   • Complete automation with cloud-init"
    echo "   • 10-15 minutes per VM"
    echo -e "${CYAN}   Command: sudo ./start_automated.sh${NC}"
    echo ""
    
    echo -e "${YELLOW}2. 📋 MANUAL INSTALLATION${NC}"
    echo "   • Requires VNC connection for each VM"
    echo "   • Manual Ubuntu installation"
    echo "   • Full control over installation process"
    echo "   • 30-45 minutes per VM"
    echo -e "${CYAN}   Command: sudo ./create_vms_manual.sh${NC}"
    echo ""
    
    echo -e "${PURPLE}3. 🔧 SEMI-AUTOMATED (Original)${NC}"
    echo "   • Automated with manual GRUB editing"
    echo "   • Uses preseed for automation"
    echo "   • Requires one manual step per VM"
    echo "   • 20-30 minutes per VM"
    echo -e "${CYAN}   Command: sudo ./start_10_vms.sh${NC}"
    echo ""
}

show_testing() {
    echo -e "${BLUE}🧪 TESTING OPTIONS:${NC}"
    echo ""
    
    echo -e "${GREEN}• Complete System Test:${NC}"
    echo -e "  ${CYAN}sudo ./test_automated_system.sh${NC}"
    echo ""
    
    echo -e "${GREEN}• System Validation:${NC}"
    echo -e "  ${CYAN}./validate_system.sh${NC}"
    echo ""
    
    echo -e "${GREEN}• Test Mode (No VMs created):${NC}"
    echo -e "  ${CYAN}sudo ./manage_vms_automated.sh --test-mode${NC}"
    echo ""
}

show_monitoring() {
    echo -e "${BLUE}📊 MONITORING OPTIONS:${NC}"
    echo ""
    
    echo -e "${GREEN}• Real-time Progress Monitor:${NC}"
    echo -e "  ${CYAN}./monitor_automated.sh${NC}"
    echo ""
    
    echo -e "${GREEN}• System Status Check:${NC}"
    echo -e "  ${CYAN}./check_status.sh${NC}"
    echo ""
    
    echo -e "${GREEN}• VM Information:${NC}"
    echo -e "  ${CYAN}cat output/vm_info.txt${NC}"
    echo ""
}

show_scaling() {
    echo -e "${BLUE}🔄 SCALING OPTIONS:${NC}"
    echo ""
    
    echo -e "${GREEN}• Scale to 20 VMs:${NC}"
    echo -e "  ${CYAN}./scale_vms.sh 20${NC}"
    echo -e "  ${CYAN}sudo ./start_automated.sh --vms 20${NC}"
    echo ""
    
    echo -e "${GREEN}• Scale back to 10 VMs:${NC}"
    echo -e "  ${CYAN}./scale_vms.sh 10${NC}"
    echo ""
    
    echo -e "${GREEN}• Custom VM count:${NC}"
    echo -e "  ${CYAN}sudo ./start_automated.sh --vms 15${NC}"
    echo ""
}

show_cleanup() {
    echo -e "${BLUE}🧹 CLEANUP OPTIONS:${NC}"
    echo ""
    
    echo -e "${GREEN}• Complete cleanup (stop all VMs):${NC}"
    echo -e "  ${CYAN}sudo ./complete_cleanup.sh${NC}"
    echo ""
    
    echo -e "${GREEN}• Standard cleanup:${NC}"
    echo -e "  ${CYAN}sudo ./cleanup_vm_environment.sh${NC}"
    echo ""
}

show_documentation() {
    echo -e "${BLUE}📚 DOCUMENTATION:${NC}"
    echo ""
    
    echo -e "${GREEN}• Automated System Guide:${NC}"
    echo -e "  ${CYAN}cat AUTOMATED_GUIDE.md${NC}"
    echo ""
    
    echo -e "${GREEN}• General Usage Guide:${NC}"
    echo -e "  ${CYAN}cat USAGE_GUIDE.md${NC}"
    echo ""
    
    echo -e "${GREEN}• Deployment Instructions:${NC}"
    echo -e "  ${CYAN}cat DEPLOYMENT_READY.md${NC}"
    echo ""
    
    echo -e "${GREEN}• System Improvements:${NC}"
    echo -e "  ${CYAN}cat IMPROVEMENTS.md${NC}"
    echo ""
}

show_examples() {
    echo -e "${BLUE}💡 EXAMPLE WORKFLOWS:${NC}"
    echo ""
    
    echo -e "${GREEN}🚀 Quick Start (Fully Automated):${NC}"
    echo -e "  ${CYAN}sudo ./test_automated_system.sh${NC}     # Test system"
    echo -e "  ${CYAN}sudo ./start_automated.sh${NC}          # Create VMs"
    echo -e "  ${CYAN}./monitor_automated.sh${NC}             # Monitor progress"
    echo ""
    
    echo -e "${GREEN}🔧 Development/Testing:${NC}"
    echo -e "  ${CYAN}./validate_system.sh${NC}               # Validate setup"
    echo -e "  ${CYAN}sudo ./manage_vms_automated.sh --test-mode${NC}  # Test config"
    echo -e "  ${CYAN}sudo ./start_automated.sh --vms 3${NC}   # Create 3 VMs only"
    echo ""
    
    echo -e "${GREEN}📈 Production Deployment:${NC}"
    echo -e "  ${CYAN}./scale_vms.sh 20${NC}                  # Scale to 20 VMs"
    echo -e "  ${CYAN}sudo ./start_automated.sh --vms 20${NC} # Create 20 VMs"
    echo -e "  ${CYAN}./check_status.sh${NC}                  # Monitor status"
    echo ""
}

show_summary() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                 SUMMARY                                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✅ System Status: READY FOR DEPLOYMENT${NC}"
    echo ""
    echo -e "${BLUE}Available VM Creation Methods:${NC}"
    echo -e "  1. ${GREEN}Fully Automated${NC} (start_automated.sh) - ${YELLOW}RECOMMENDED${NC}"
    echo -e "  2. ${GREEN}Manual Installation${NC} (create_vms_manual.sh)"
    echo -e "  3. ${GREEN}Semi-Automated${NC} (start_10_vms.sh)"
    echo ""
    echo -e "${BLUE}Key Features:${NC}"
    echo -e "  ✅ Complete automation available"
    echo -e "  ✅ Scalable (10-20 VMs)"
    echo -e "  ✅ Real-time monitoring"
    echo -e "  ✅ Comprehensive testing"
    echo -e "  ✅ Full documentation"
    echo ""
    echo -e "${GREEN}🚀 Ready to create your VM infrastructure!${NC}"
    echo ""
}

main() {
    show_header
    show_options
    show_testing
    show_monitoring
    show_scaling
    show_cleanup
    show_documentation
    show_examples
    show_summary
    
    echo -e "${YELLOW}Choose your preferred method and start creating VMs!${NC}"
    echo ""
}

# Show interactive menu if run without arguments
if [ $# -eq 0 ]; then
    main
    exit 0
fi

# Handle command line arguments
case "$1" in
    "test")
        echo "Running system test..."
        exec sudo ./test_automated_system.sh
        ;;
    "start")
        echo "Starting automated VM creation..."
        exec sudo ./start_automated.sh
        ;;
    "monitor")
        echo "Starting monitoring..."
        exec ./monitor_automated.sh
        ;;
    "status")
        echo "Checking system status..."
        exec ./check_status.sh
        ;;
    "cleanup")
        echo "Cleaning up system..."
        exec sudo ./complete_cleanup.sh
        ;;
    "help"|"--help"|"-h")
        main
        ;;
    *)
        echo "Usage: $0 [test|start|monitor|status|cleanup|help]"
        echo "Run without arguments to see all options."
        ;;
esac