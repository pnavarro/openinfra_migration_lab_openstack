#!/bin/bash
# RHOSO Deployment Script for SSH Jump Host (Bastion) connectivity
# This script runs from jumphost, SSHs to bastion, and executes deployment locally on bastion

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
    
    # Extract bastion connection details from inventory
    local bastion_host=$(grep "bastion_hostname:" inventory/hosts.yml | sed "s/.*bastion_hostname: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
    local bastion_port=$(grep "bastion_port:" inventory/hosts.yml | sed "s/.*bastion_port: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
    local bastion_user=$(grep "bastion_user:" inventory/hosts.yml | sed "s/.*bastion_user: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
    local bastion_password=$(grep "bastion_password:" inventory/hosts.yml | sed "s/.*bastion_password: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
    
    [[ -z "$bastion_user" ]] && bastion_user="lab-user"
    
    print_status "Bastion connection: ${bastion_user}@${bastion_host}:${bastion_port}"
    
    # Setup deployment environment on bastion
    print_status "Setting up deployment environment on bastion..."
    local setup_commands="
        mkdir -p /home/$bastion_user/rhoso-deployment/ansible-playbooks
        
        # Install required packages if not present
        if ! command -v ansible &> /dev/null; then
            echo 'Installing Ansible...'
            if command -v dnf &> /dev/null; then
                sudo dnf install -y ansible python3-pip sshpass || echo 'Failed to install via dnf'
            elif command -v yum &> /dev/null; then
                sudo yum install -y ansible python3-pip sshpass || echo 'Failed to install via yum'
            fi
        fi
        
        # Ensure sshpass is available for SSH proxy functionality
        if ! command -v sshpass &> /dev/null; then
            echo 'Installing sshpass for SSH proxy functionality...'
            if command -v dnf &> /dev/null; then
                sudo dnf install -y sshpass || echo 'Failed to install sshpass via dnf'
            elif command -v yum &> /dev/null; then
                sudo yum install -y sshpass || echo 'Failed to install sshpass via yum'
            fi
        fi
        
        # Install required Python libraries for Ansible and Kubernetes operations
        echo 'Installing required Python libraries...'
        
        # Install for default python3
        python3 -m pip install --user --upgrade pip
        python3 -m pip install --user kubernetes openshift jmespath pyyaml requests urllib3
        
        # Also ensure libraries are available for Python 3.11 (which Ansible uses)
        if command -v python3.11 &> /dev/null; then
            echo 'Installing libraries for Python 3.11...'
            # Install pip for Python 3.11 if not available
            if ! python3.11 -m pip --version &> /dev/null; then
                sudo dnf install -y python3.11-pip || sudo yum install -y python3.11-pip || echo 'Could not install python3.11-pip'
            fi
            python3.11 -m pip install --user --upgrade pip
            python3.11 -m pip install --user kubernetes openshift jmespath pyyaml requests urllib3
        fi
        
        # Try installing via system packages as fallback
        echo 'Installing system packages as fallback...'
        if command -v dnf &> /dev/null; then
            sudo dnf install -y python3-kubernetes python3-jmespath python3-yaml python3-requests || echo 'Some system packages failed to install'
        elif command -v yum &> /dev/null; then
            sudo yum install -y python3-kubernetes python3-jmespath python3-yaml python3-requests || echo 'Some system packages failed to install'
        fi
    "
    
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" ]]; then
        sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$setup_commands"
    else
        print_warning "sshpass not available or no password. You may need to enter password manually."
        ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$setup_commands"
    fi
    
    # Copy deployment files to bastion
    print_status "Copying deployment files to bastion..."
    local temp_dir="/tmp/rhoso-deploy-$$"
    mkdir -p "$temp_dir"
    
    # Copy all necessary files
    cp -r ./* "$temp_dir/"
    
    # Ensure sshpass is available for SSH proxy commands
    if ! command -v sshpass &> /dev/null; then
        print_warning "sshpass not found. Installing sshpass on bastion for SSH proxy functionality..."
    fi
    
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" ]]; then
        sshpass -p "$bastion_password" scp -o StrictHostKeyChecking=no -P "$bastion_port" -r "$temp_dir"/* "$bastion_user@$bastion_host:/home/$bastion_user/rhoso-deployment/ansible-playbooks/"
    else
        scp -o StrictHostKeyChecking=no -P "$bastion_port" -r "$temp_dir"/* "$bastion_user@$bastion_host:/home/$bastion_user/rhoso-deployment/ansible-playbooks/"
    fi
    
    rm -rf "$temp_dir"
    
    # Prepare ansible options
    local ansible_opts=""
    if [[ "$dry_run" == "true" ]]; then
        ansible_opts="--check --diff"
        print_warning "Running in DRY RUN mode - no changes will be made"
    fi
    
    if [[ "$verbose" == "true" ]]; then
        ansible_opts="$ansible_opts -vv"
    fi
    
    # Prepare deployment command to run on bastion
    local deployment_cmd="
        cd /home/$bastion_user/rhoso-deployment/ansible-playbooks
        
        # Install required collections
        ansible-galaxy collection install -r requirements.yml --force
        
        # Run the deployment locally on bastion
        case '$phase' in
            'prerequisites')
                echo 'Running prerequisites phase...'
                ansible-playbook site.yml --tags prerequisites $ansible_opts
                ;;
            'install-operators')
                echo 'Installing OpenStack operators...'
                ansible-playbook site.yml --tags install-operators $ansible_opts
                ;;
            'security')
                echo 'Configuring security...'
                ansible-playbook site.yml --tags security $ansible_opts
                ;;
            'nfs-server')
                echo 'Configuring NFS server...'
                ansible-playbook site.yml --tags nfs-server $ansible_opts
                ;;
            'network-isolation')
                echo 'Setting up network isolation...'
                ansible-playbook site.yml --tags network-isolation $ansible_opts
                ;;
            'control-plane')
                echo 'Deploying control plane...'
                ansible-playbook site.yml --tags control-plane $ansible_opts
                ;;
            'data-plane')
                echo 'Configuring data plane...'
                ansible-playbook site.yml --tags data-plane $ansible_opts
                ;;
            'validation')
                echo 'Running validation...'
                ansible-playbook site.yml --tags validation $ansible_opts
                ;;
            'full')
                echo 'Running complete deployment...'
                ansible-playbook site.yml $ansible_opts
                ;;
            'optional')
                echo 'Enabling optional services (Heat, Swift)...'
                ansible-playbook optional-services.yml $ansible_opts
                ;;
            *)
                echo 'Unknown phase: $phase'
                exit 1
                ;;
        esac
    "
    
    # Execute deployment on bastion
    print_header "Running $phase phase on bastion host..."
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" ]]; then
        sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$deployment_cmd"
    else
        ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$deployment_cmd"
    fi
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
