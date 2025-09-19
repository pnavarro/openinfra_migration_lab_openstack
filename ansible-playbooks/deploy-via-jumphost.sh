#!/bin/bash
# RHOSO Deployment Script for SSH Jump Host (Bastion) connectivity
# This script is designed to run from your local workstation and connect to the bastion

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [PHASE]"
    echo ""
    echo "This script deploys RHOSO by connecting to your bastion host."
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --check-inventory   Check inventory configuration"
    echo "  -d, --dry-run          Run in check mode (no changes)"
    echo "  -v, --verbose          Enable verbose output"
    echo ""
    echo "Available phases:"
    echo "  prerequisites  - Install required operators (NMState, MetalLB)"
    echo "  install-operators - Install OpenStack operators"
    echo "  security      - Configure secrets and security"
    echo "  nfs-server    - Configure NFS server"
    echo "  network-isolation - Set up network isolation"
    echo "  control-plane - Deploy OpenStack control plane"
    echo "  data-plane    - Configure compute nodes"
    echo "  validation    - Verify deployment"
    echo "  full          - Run complete deployment (default)"
    echo "  optional      - Enable optional services (Heat, Swift)"
    echo ""
    echo "Examples:"
    echo "  $0                         # Run full deployment"
    echo "  $0 full                    # Run full deployment"
    echo "  $0 -c                      # Check inventory configuration"
    echo "  $0 -d control-plane        # Dry run of control plane deployment"
    echo "  $0 -v prerequisites        # Verbose prerequisites installation"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed. Please install Ansible 2.12 or newer."
        exit 1
    fi
    
    # Check ansible version
    local ansible_version=$(ansible --version | head -1 | cut -d' ' -f3)
    print_status "Found Ansible version: $ansible_version"
    
    # Check if inventory file exists
    if [[ ! -f "inventory/hosts.yml" ]]; then
        print_error "Inventory file inventory/hosts.yml not found."
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Function to check inventory configuration
check_inventory() {
    print_header "Checking inventory configuration..."
    
    if grep -q "changeme" inventory/hosts.yml; then
        print_error "Inventory file contains default 'changeme' values."
        echo ""
        echo "Please update the following in inventory/hosts.yml:"
        echo "  - lab_guid: Your lab GUID"
        echo "  - bastion_hostname: Your bastion hostname (e.g., ssh.ocpvdev01.rhdp.net)"
        echo "  - bastion_port: Your SSH port (e.g., 31295)"
        echo "  - bastion_password: Your bastion password"
        echo "  - registry_username: Red Hat registry service account username"
        echo "  - registry_password: Red Hat registry service account password/token"
        echo "  - rhc_username: Red Hat Customer Portal username"
        echo "  - rhc_password: Red Hat Customer Portal password"
        echo ""
        return 1
    fi
    
    # Test SSH connectivity to bastion
    print_status "Testing SSH connectivity to bastion..."
    local bastion_host=$(grep "bastion_hostname:" inventory/hosts.yml | cut -d'"' -f2)
    local bastion_port=$(grep "bastion_port:" inventory/hosts.yml | cut -d'"' -f2)
    local bastion_user=$(grep "bastion_user:" inventory/hosts.yml | cut -d'"' -f2)
    
    if [[ "$bastion_host" == *"example.com"* ]]; then
        print_warning "Bastion hostname still contains 'example.com'. Please update it."
        return 1
    fi
    
    print_status "Inventory configuration looks good!"
    print_status "Bastion: ${bastion_user}@${bastion_host}:${bastion_port}"
    return 0
}

# Function to install required collections
install_collections() {
    print_status "Installing required Ansible collections..."
    ansible-galaxy collection install -r requirements.yml --force
}

# Function to run deployment
run_deployment() {
    local phase="$1"
    local dry_run="$2"
    local verbose="$3"
    
    local ansible_opts=""
    if [[ "$dry_run" == "true" ]]; then
        ansible_opts="--check --diff"
        print_warning "Running in DRY RUN mode - no changes will be made"
    fi
    
    if [[ "$verbose" == "true" ]]; then
        ansible_opts="$ansible_opts -vv"
    fi
    
    case "$phase" in
        "prerequisites")
            print_header "Running prerequisites phase..."
            ansible-playbook site.yml --tags prerequisites $ansible_opts
            ;;
        "install-operators")
            print_header "Installing OpenStack operators..."
            ansible-playbook site.yml --tags install-operators $ansible_opts
            ;;
        "security")
            print_header "Configuring security..."
            ansible-playbook site.yml --tags security $ansible_opts
            ;;
        "nfs-server")
            print_header "Configuring NFS server..."
            ansible-playbook site.yml --tags nfs-server $ansible_opts
            ;;
        "network-isolation")
            print_header "Setting up network isolation..."
            ansible-playbook site.yml --tags network-isolation $ansible_opts
            ;;
        "control-plane")
            print_header "Deploying control plane..."
            ansible-playbook site.yml --tags control-plane $ansible_opts
            ;;
        "data-plane")
            print_header "Configuring data plane..."
            ansible-playbook site.yml --tags data-plane $ansible_opts
            ;;
        "validation")
            print_header "Running validation..."
            ansible-playbook site.yml --tags validation $ansible_opts
            ;;
        "full")
            print_header "Running complete deployment..."
            ansible-playbook site.yml $ansible_opts
            ;;
        "optional")
            print_header "Enabling optional services (Heat, Swift)..."
            ansible-playbook optional-services.yml $ansible_opts
            ;;
        *)
            print_error "Unknown phase: $phase"
            echo "Available phases: prerequisites, install-operators, security, nfs-server, network-isolation, control-plane, data-plane, validation, full, optional"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    local phase="full"
    local check_only="false"
    local dry_run="false"
    local verbose="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--check-inventory)
                check_only="true"
                shift
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                phase="$1"
                shift
                ;;
        esac
    done
    
    print_header "RHOSO Deployment via Jump Host - Phase: $phase"
    print_status "Timestamp: $(date)"
    print_status "Working directory: $(pwd)"
    
    check_prerequisites
    
    if [[ "$check_only" == "true" ]]; then
        check_inventory
        exit 0
    fi
    
    if ! check_inventory; then
        print_error "Inventory check failed. Please fix the configuration and try again."
        exit 1
    fi
    
    install_collections
    run_deployment "$phase" "$dry_run" "$verbose"
    
    if [[ "$dry_run" == "true" ]]; then
        print_status "Dry run completed successfully!"
        print_status "Run without -d/--dry-run to perform actual deployment."
    else
        print_status "Deployment phase '$phase' completed successfully!"
        print_status "Check the README.md for verification commands and troubleshooting."
    fi
}

# Run main function with all arguments
main "$@"
