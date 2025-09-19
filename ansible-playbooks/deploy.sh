#!/bin/bash
# RHOSO Deployment Script
# This script automates the complete deployment of Red Hat OpenStack Services on OpenShift

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed. Please install Ansible 2.12 or newer."
        exit 1
    fi
    
    # Check if oc is installed and configured
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) is not installed or not in PATH."
        exit 1
    fi
    
    # Check if we can connect to OpenShift cluster
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster. Please run 'oc login' first."
        exit 1
    fi
    
    # Check if inventory file has been customized
    if grep -q "changeme" inventory/hosts.yml; then
        print_error "Inventory file contains default 'changeme' values. Please update inventory/hosts.yml with your lab environment details."
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Function to install required collections
install_collections() {
    print_status "Installing required Ansible collections..."
    ansible-galaxy collection install -r requirements.yml --force
}

# Function to run deployment
run_deployment() {
    local phase="$1"
    
    case "$phase" in
        "prerequisites")
            print_status "Running prerequisites phase..."
            ansible-playbook site.yml --limit bastion --tags prerequisites
            ;;
        "operators")
            print_status "Installing OpenStack operators..."
            ansible-playbook site.yml --limit bastion --tags install-operators
            ;;
        "nfs")
            print_status "Configuring NFS server..."
            ansible-playbook site.yml --limit nfsserver
            ;;
        "network")
            print_status "Setting up network isolation..."
            ansible-playbook site.yml --limit bastion --tags network-isolation
            ;;
        "security")
            print_status "Configuring security..."
            ansible-playbook site.yml --limit bastion --tags security
            ;;
        "controlplane")
            print_status "Deploying control plane..."
            ansible-playbook site.yml --limit bastion --tags control-plane
            ;;
        "dataplane")
            print_status "Configuring data plane..."
            ansible-playbook site.yml --limit bastion --tags data-plane
            ;;
        "validation")
            print_status "Running validation..."
            ansible-playbook site.yml --limit bastion --tags validation
            ;;
        "full")
            print_status "Running complete deployment..."
            ansible-playbook site.yml
            ;;
        "optional")
            print_status "Enabling optional services (Heat, Swift)..."
            ansible-playbook optional-services.yml
            ;;
        *)
            print_error "Unknown phase: $phase"
            echo "Available phases: prerequisites, operators, nfs, network, security, controlplane, dataplane, validation, full, optional"
            exit 1
            ;;
    esac
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [PHASE]"
    echo ""
    echo "Available phases:"
    echo "  prerequisites  - Install required operators (NMState, MetalLB)"
    echo "  operators      - Install OpenStack operators"
    echo "  nfs           - Configure NFS server"
    echo "  network       - Set up network isolation"
    echo "  security      - Configure secrets and security"
    echo "  controlplane  - Deploy OpenStack control plane"
    echo "  dataplane     - Configure compute nodes"
    echo "  validation    - Verify deployment"
    echo "  full          - Run complete deployment (default)"
    echo "  optional      - Enable optional services (Heat, Swift)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run full deployment"
    echo "  $0 full              # Run full deployment"
    echo "  $0 prerequisites     # Install prerequisites only"
    echo "  $0 controlplane      # Deploy control plane only"
}

# Main execution
main() {
    local phase="${1:-full}"
    
    if [[ "$phase" == "-h" || "$phase" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    print_status "Starting RHOSO deployment - Phase: $phase"
    print_status "Timestamp: $(date)"
    
    check_prerequisites
    install_collections
    run_deployment "$phase"
    
    print_status "Deployment phase '$phase' completed successfully!"
    print_status "Check the README.md for verification commands and troubleshooting."
}

# Run main function with all arguments
main "$@"
