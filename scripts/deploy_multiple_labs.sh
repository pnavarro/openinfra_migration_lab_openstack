#!/bin/bash
# Multi-Lab RHOSO Deployment Script
# This script orchestrates the deployment of multiple RHOSO labs based on a configuration file

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PROJECT_ROOT/ansible-playbooks"
PARSER_SCRIPT="$SCRIPT_DIR/parse_lab_config.py"
GENERATED_INVENTORIES_DIR="$ANSIBLE_DIR/generated_inventories"
LOG_DIR="$PROJECT_ROOT/deployment_logs"

# Default values
MAX_PARALLEL_JOBS=3
DEPLOYMENT_PHASE="full"
DRY_RUN=false
VERBOSE=false
FORCE_REGENERATE=false

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

print_lab() {
    echo -e "${PURPLE}[LAB]${NC} $1"
}

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] <lab_config_file>"
    echo ""
    echo "Deploy multiple RHOSO labs based on a configuration file."
    echo ""
    echo "Arguments:"
    echo "  lab_config_file         Path to the lab configuration file"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --check-inventory   Check inventory configuration only"
    echo "  -j, --jobs NUM          Maximum parallel jobs (default: $MAX_PARALLEL_JOBS)"
    echo "  -p, --phase PHASE       Deployment phase (default: $DEPLOYMENT_PHASE)"
    echo "  -d, --dry-run          Run in check mode (no changes)"
    echo "  -v, --verbose          Enable verbose output"
    echo "  -f, --force            Force regeneration of inventory files"
    echo "  --credentials FILE      File containing registry and RH credentials"
    echo ""
    echo "Available phases:"
    echo "  prerequisites           Install required operators (NMState, MetalLB)"
    echo "  install-operators      Install OpenStack operators"
    echo "  security               Configure secrets and security"
    echo "  nfs-server             Configure NFS server"
    echo "  network-isolation      Set up network isolation"
    echo "  control-plane          Deploy OpenStack control plane"
    echo "  data-plane             Configure compute nodes"
    echo "  validation             Verify deployment"
    echo "  full                   Run complete deployment (default)"
    echo "  optional               Enable optional services (Heat, Swift)"
    echo ""
    echo "Credentials file format (YAML):"
    echo "  registry_username: \"12345678|myserviceaccount\""
    echo "  registry_password: \"eyJhbGciOiJSUzUxMiJ9...\""
    echo "  rhc_username: \"your-rh-username@email.com\""
    echo "  rhc_password: \"YourRHPassword123\""
    echo ""
    echo "Examples:"
    echo "  $0 labs_to_be_deployed                    # Deploy all labs"
    echo "  $0 -c labs_to_be_deployed                 # Check inventory configuration only"
    echo "  $0 -j 2 -p prerequisites labs_to_be_deployed  # Deploy prerequisites with 2 parallel jobs"
    echo "  $0 -d -v labs_to_be_deployed              # Dry run with verbose output"
    echo "  $0 --credentials creds.yml labs_to_be_deployed  # Use credentials file"
}

# Function to check prerequisites (enhanced like deploy-via-jumphost.sh)
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is not installed. Please install Ansible 2.12 or newer."
        exit 1
    fi
    
    # Check ansible version
    local ansible_version=$(ansible --version | head -1 | cut -d' ' -f3)
    print_status "Found Ansible version: $ansible_version"
    
    # Check if required Python modules are available
    if ! python3 -c "import yaml" &> /dev/null; then
        print_error "PyYAML is not installed. Please install it: pip3 install PyYAML"
        exit 1
    fi
    
    # Check if parser script exists
    if [[ ! -f "$PARSER_SCRIPT" ]]; then
        print_error "Parser script not found: $PARSER_SCRIPT"
        exit 1
    fi
    
    # Check if we're in the right directory structure
    if [[ ! -f "$ANSIBLE_DIR/site.yml" ]]; then
        print_error "Main playbook site.yml not found in $ANSIBLE_DIR"
        print_error "Please run this script from the project root directory"
        exit 1
    fi
    
    # Check if requirements.yml exists
    if [[ ! -f "$ANSIBLE_DIR/requirements.yml" ]]; then
        print_error "Ansible requirements file not found: $ANSIBLE_DIR/requirements.yml"
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Function to install required collections globally (like deploy-via-jumphost.sh)
install_collections() {
    print_status "Installing required Ansible collections globally..."
    
    cd "$ANSIBLE_DIR"
    
    if ! ansible-galaxy collection install -r requirements.yml --force; then
        print_error "Failed to install required Ansible collections"
        exit 1
    fi
    
    print_status "Ansible collections installed successfully"
}

# Function to create necessary directories
setup_directories() {
    print_status "Setting up directories..."
    
    mkdir -p "$GENERATED_INVENTORIES_DIR"
    mkdir -p "$LOG_DIR"
    
    print_status "Directories created/verified."
}

# Function to parse lab configuration
parse_lab_config() {
    local config_file="$1"
    
    print_header "Parsing lab configuration file: $config_file"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Lab configuration file not found: $config_file"
        exit 1
    fi
    
    # Convert to absolute path before changing directories
    config_file="$(realpath "$config_file")"
    
    # Change to the ansible directory to run the parser
    cd "$ANSIBLE_DIR"
    
    # Run the parser script
    if ! python3 "$PARSER_SCRIPT" "$config_file"; then
        print_error "Failed to parse lab configuration file"
        exit 1
    fi
    
    print_status "Lab configuration parsed successfully."
}

# Function to update inventory files with credentials
update_credentials() {
    local credentials_file="$1"
    
    if [[ -z "$credentials_file" || ! -f "$credentials_file" ]]; then
        print_warning "No credentials file provided. You'll need to manually update registry and RH credentials in inventory files."
        return
    fi
    
    print_status "Updating inventory files with credentials from: $credentials_file"
    
    # Copy the Python updater script to a temporary location
    cat > /tmp/credentials_updater.py << 'PYTHON_EOF'
#!/usr/bin/env python3
import sys
import re

def update_inventory_credentials(inventory_file, credentials_file):
    # Read credentials
    creds = {}
    try:
        with open(credentials_file, 'r') as f:
            for line in f:
                line = line.strip()
                if ':' in line and not line.startswith('#'):
                    key, value = line.split(':', 1)
                    key = key.strip()
                    value = value.strip().strip('"')
                    if value and not value.startswith('REPLACE_WITH'):
                        creds[key] = value
    except Exception as e:
        return False
    
    if not creds:
        return True
    
    # Read inventory file
    try:
        with open(inventory_file, 'r') as f:
            content = f.read()
    except Exception as e:
        return False
    
    # Update credentials in inventory
    updated = False
    for key, value in creds.items():
        # Escape special characters for JSON
        escaped_value = value.replace('\\', '\\\\').replace('"', '\\"')
        pattern = f'{key}: "[^"]*"'
        replacement = f'{key}: "{escaped_value}"'
        if re.search(pattern, content):
            content = re.sub(pattern, replacement, content)
            updated = True
    
    # Write back if updated
    if updated:
        try:
            with open(inventory_file, 'w') as f:
                f.write(content)
            return True
        except Exception as e:
            return False
    return True

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(1)
    success = update_inventory_credentials(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)
PYTHON_EOF
    
    # Update all inventory files using the Python script
    for inventory_file in "$GENERATED_INVENTORIES_DIR"/hosts-cluster-*.yml; do
        if [[ -f "$inventory_file" ]]; then
            print_status "Updating credentials in: $(basename "$inventory_file")"
            
            if ! python3 /tmp/credentials_updater.py "$inventory_file" "$credentials_file"; then
                print_warning "Failed to update credentials in $(basename "$inventory_file")"
            fi
        fi
    done
    
    # Clean up
    rm -f /tmp/credentials_updater.py
}

# Function to check individual inventory configuration (similar to deploy-via-jumphost.sh)
check_inventory_file() {
    local inventory_file="$1"
    local lab_guid="$2"
    
    print_status "Checking inventory configuration for lab: $lab_guid"
    
    # Check for 'changeme' values
    if grep -q "changeme" "$inventory_file"; then
        print_error "Inventory file for lab $lab_guid contains default 'changeme' values."
        echo ""
        echo "Please update the following in $inventory_file:"
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
    
    # Test SSH connectivity to bastion (if possible)
    local bastion_host=$(grep "bastion_hostname:" "$inventory_file" | cut -d'"' -f2)
    local bastion_port=$(grep "bastion_port:" "$inventory_file" | cut -d'"' -f2)
    local bastion_user=$(grep "bastion_user:" "$inventory_file" | cut -d'"' -f2 || echo "lab-user")
    
    if [[ "$bastion_host" == *"example.com"* ]]; then
        print_warning "Lab $lab_guid: Bastion hostname still contains 'example.com'. Please update it."
        return 1
    fi
    
    # Basic connectivity test (non-blocking)
    if command -v nc &> /dev/null && [[ -n "$bastion_host" && -n "$bastion_port" ]]; then
        print_status "Testing SSH connectivity to bastion for lab $lab_guid: ${bastion_user}@${bastion_host}:${bastion_port}"
        if timeout 5 nc -z "$bastion_host" "$bastion_port" 2>/dev/null; then
            print_status "✅ Lab $lab_guid: Bastion connectivity test passed"
        else
            print_warning "⚠️  Lab $lab_guid: Bastion connectivity test failed (may be due to firewall/network)"
            print_warning "    This may not prevent deployment if bastion is accessible from Ansible control node"
        fi
    fi
    
    print_status "Lab $lab_guid: Inventory configuration looks good!"
    print_status "Lab $lab_guid: Bastion: ${bastion_user}@${bastion_host}:${bastion_port}"
    return 0
}

# Function to validate inventory files with enhanced checks
validate_inventories() {
    print_status "Validating generated inventory files..."
    
    local inventory_files=("$GENERATED_INVENTORIES_DIR"/hosts-cluster-*.yml)
    local valid_count=0
    local failed_labs=()
    
    for inventory_file in "${inventory_files[@]}"; do
        if [[ -f "$inventory_file" ]]; then
            # Extract lab GUID from filename
            local filename=$(basename "$inventory_file")
            local lab_guid=$(echo "$filename" | sed 's/hosts-cluster-\(.*\)\.yml/\1/')
            
            if check_inventory_file "$inventory_file" "$lab_guid"; then
                ((valid_count++))
            else
                failed_labs+=("$lab_guid")
            fi
            echo
        fi
    done
    
    print_status "Validated $valid_count inventory files successfully."
    
    if [[ ${#failed_labs[@]} -gt 0 ]]; then
        print_error "Failed validation for labs: ${failed_labs[*]}"
        print_error "Please fix the configuration issues and try again."
        return 1
    fi
    
    if [[ $valid_count -eq 0 ]]; then
        print_error "No valid inventory files found!"
        return 1
    fi
    
    return 0
}

# Function to deploy a single lab
deploy_lab() {
    local inventory_file="$1"
    local lab_guid="$2"
    local phase="$3"
    local dry_run="$4"
    local verbose="$5"
    
    local log_file="$LOG_DIR/deploy_${lab_guid}_$(date +%Y%m%d_%H%M%S).log"
    
    print_lab "Starting deployment for lab: $lab_guid"
    print_lab "Log file: $log_file"
    
    # Prepare ansible options
    local ansible_opts=""
    if [[ "$dry_run" == "true" ]]; then
        ansible_opts="--check --diff"
    fi
    
    if [[ "$verbose" == "true" ]]; then
        ansible_opts="$ansible_opts -vv"
    fi
    
    # Change to ansible directory
    cd "$ANSIBLE_DIR"
    
    # Collections are installed globally, so we can skip per-lab installation
    print_lab "[$lab_guid] Using globally installed Ansible collections"
    
    # Run the deployment
    local start_time=$(date +%s)
    print_lab "[$lab_guid] Starting $phase deployment..."
    
    local playbook_cmd
    case "$phase" in
        "full")
            playbook_cmd="ansible-playbook -i \"$inventory_file\" site.yml $ansible_opts"
            ;;
        "optional")
            playbook_cmd="ansible-playbook -i \"$inventory_file\" optional-services.yml $ansible_opts"
            ;;
        *)
            playbook_cmd="ansible-playbook -i \"$inventory_file\" site.yml --tags \"$phase\" $ansible_opts"
            ;;
    esac
    
    # Execute the playbook
    if eval "$playbook_cmd" >> "$log_file" 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_lab "[$lab_guid] ✅ Deployment completed successfully in ${duration}s"
        return 0
    else
        print_lab "[$lab_guid] ❌ Deployment failed - check log: $log_file"
        return 1
    fi
}

# Function to deploy all labs
deploy_all_labs() {
    local phase="$1"
    local dry_run="$2"
    local verbose="$3"
    local max_jobs="$4"
    
    print_header "Starting deployment of all labs (phase: $phase, max parallel jobs: $max_jobs)"
    
    local inventory_files=("$GENERATED_INVENTORIES_DIR"/hosts-cluster-*.yml)
    local total_labs=${#inventory_files[@]}
    local completed_count=0
    local failed_count=0
    local pids=()
    local lab_pids=()
    
    if [[ $total_labs -eq 0 ]]; then
        print_error "No inventory files found in $GENERATED_INVENTORIES_DIR"
        exit 1
    fi
    
    print_status "Found $total_labs labs to deploy"
    
    # Deploy labs with parallelism control
    for inventory_file in "${inventory_files[@]}"; do
        if [[ ! -f "$inventory_file" ]]; then
            continue
        fi
        
        # Extract lab GUID from filename
        local filename=$(basename "$inventory_file")
        local lab_guid=$(echo "$filename" | sed 's/hosts-cluster-\(.*\)\.yml/\1/')
        
        # Wait if we've reached max parallel jobs
        while [[ ${#pids[@]} -ge $max_jobs ]]; do
            sleep 1
            # Check for completed jobs
            local new_pids=()
            local new_lab_pids=()
            for i in "${!pids[@]}"; do
                if kill -0 "${pids[$i]}" 2>/dev/null; then
                    new_pids+=("${pids[$i]}")
                    new_lab_pids+=("${lab_pids[$i]}")
                else
                    # Job completed, check return code
                    wait "${pids[$i]}"
                    local exit_code=$?
                    if [[ $exit_code -eq 0 ]]; then
                        ((completed_count++))
                    else
                        ((failed_count++))
                    fi
                    print_progress "Progress: $((completed_count + failed_count))/$total_labs completed"
                fi
            done
            pids=("${new_pids[@]}")
            lab_pids=("${new_lab_pids[@]}")
        done
        
        # Start deployment for this lab in background
        (deploy_lab "$inventory_file" "$lab_guid" "$phase" "$dry_run" "$verbose") &
        local pid=$!
        pids+=("$pid")
        lab_pids+=("$lab_guid")
        
        print_status "Started deployment for lab $lab_guid (PID: $pid)"
    done
    
    # Wait for all remaining jobs to complete
    print_status "Waiting for remaining deployments to complete..."
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            ((completed_count++))
        else
            ((failed_count++))
        fi
        print_progress "Progress: $((completed_count + failed_count))/$total_labs completed"
    done
    
    # Print final summary
    print_header "Deployment Summary"
    print_status "Total labs: $total_labs"
    print_status "Completed successfully: $completed_count"
    if [[ $failed_count -gt 0 ]]; then
        print_error "Failed deployments: $failed_count"
        print_status "Check log files in $LOG_DIR for details"
    else
        print_status "All deployments completed successfully! 🎉"
    fi
    
    return $failed_count
}

# Function to list available labs
list_labs() {
    local config_file="$1"
    
    print_header "Available labs in configuration file:"
    
    # Quick parse to show lab info
    if command -v python3 &> /dev/null; then
        python3 -c "
import re
import sys

def extract_labs(content):
    service_blocks = re.split(r'^(openshift-cnv\.osp-on-ocp-cnv\.(?:dev|prod)-\w+)', content, flags=re.MULTILINE)
    labs = []
    
    for i in range(1, len(service_blocks), 2):
        if i + 1 < len(service_blocks):
            service_name = service_blocks[i].strip()
            service_content = service_blocks[i + 1]
            
            # Extract GUID from YAML data section (preferred method)
            yaml_guid_match = re.search(r'guid:\s*(\w+)', service_content)
            if yaml_guid_match:
                guid = yaml_guid_match.group(1)
            else:
                # Fallback: Extract GUID from service name
                guid_match = re.search(r'-(\w+)$', service_name)
                guid = guid_match.group(1) if guid_match else 'unknown'
            
            # Extract bastion info
            ssh_match = re.search(r'ssh lab-user@(\S+) -p (\d+)', service_content)
            bastion_info = f'{ssh_match.group(1)}:{ssh_match.group(2)}' if ssh_match else 'N/A'
            
            labs.append((guid, service_name, bastion_info))
    
    return labs

try:
    with open('$config_file', 'r') as f:
        content = f.read()
    
    labs = extract_labs(content)
    
    for guid, service, bastion in labs:
        print(f'  • Lab GUID: {guid}')
        print(f'    Service: {service}')
        print(f'    Bastion: {bastion}')
        print()
    
    print(f'Total: {len(labs)} labs found')
    
except Exception as e:
    print(f'Error parsing file: {e}')
    sys.exit(1)
"
    else
        print_error "Python 3 not available for parsing"
        exit 1
    fi
}

# Main execution
main() {
    local config_file=""
    local credentials_file=""
    local list_only=false
    local check_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--check-inventory)
                check_only=true
                shift
                ;;
            -j|--jobs)
                MAX_PARALLEL_JOBS="$2"
                shift 2
                ;;
            -p|--phase)
                DEPLOYMENT_PHASE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE_REGENERATE=true
                shift
                ;;
            --credentials)
                credentials_file="$2"
                shift 2
                ;;
            --list)
                list_only=true
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$config_file" ]]; then
                    config_file="$1"
                else
                    print_error "Multiple config files specified"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$config_file" ]]; then
        print_error "Lab configuration file is required"
        show_usage
        exit 1
    fi
    
    if [[ "$list_only" == "true" ]]; then
        list_labs "$config_file"
        exit 0
    fi
    
    print_header "Multi-Lab RHOSO Deployment"
    print_status "Timestamp: $(date)"
    print_status "Configuration file: $config_file"
    print_status "Deployment phase: $DEPLOYMENT_PHASE"
    print_status "Max parallel jobs: $MAX_PARALLEL_JOBS"
    print_status "Dry run: $DRY_RUN"
    print_status "Verbose: $VERBOSE"
    
    check_prerequisites
    setup_directories
    
    # Parse lab configuration (force regenerate if requested)
    if [[ "$FORCE_REGENERATE" == "true" ]] || [[ ! -d "$GENERATED_INVENTORIES_DIR" ]] || [[ -z "$(ls -A "$GENERATED_INVENTORIES_DIR" 2>/dev/null)" ]]; then
        parse_lab_config "$config_file"
    else
        print_status "Using existing inventory files (use -f/--force to regenerate)"
    fi
    
    # Update credentials if provided
    if [[ -n "$credentials_file" ]]; then
        update_credentials "$credentials_file"
    fi
    
    # Validate inventories with enhanced checks
    if ! validate_inventories; then
        print_error "Inventory validation failed. Please fix the issues and try again."
        exit 1
    fi
    
    # If check-only mode, exit after validation
    if [[ "$check_only" == "true" ]]; then
        print_status "✅ Inventory validation completed successfully!"
        print_status "All lab configurations are ready for deployment."
        exit 0
    fi
    
    # Install required Ansible collections globally
    install_collections
    
    # Deploy all labs
    if deploy_all_labs "$DEPLOYMENT_PHASE" "$DRY_RUN" "$VERBOSE" "$MAX_PARALLEL_JOBS"; then
        print_status "🎉 All lab deployments completed successfully!"
        exit 0
    else
        print_error "Some lab deployments failed. Check the logs for details."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"

