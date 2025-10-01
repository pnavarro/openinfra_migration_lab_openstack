#!/bin/bash
# Multi-Lab RHOSO Deployment Script (Bastion Execution Model)
# This script runs FROM JUMPHOST and deploys to multiple bastion hosts
# Each deployment runs LOCALLY on the bastion host (original design)

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
    echo "Deploy multiple RHOSO labs using the BASTION EXECUTION MODEL."
    echo "This script runs from jumphost and executes deployments ON each bastion host."
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
    echo "Architecture:"
    echo "  Jumphost → SSH to Bastion Host → Run deployment locally on bastion"
    echo ""
    echo "Examples:"
    echo "  $0 labs_to_be_deployed                    # Deploy all labs"
    echo "  $0 -c labs_to_be_deployed                 # Check inventory configuration only"
    echo "  $0 -j 2 -p prerequisites labs_to_be_deployed  # Deploy prerequisites with 2 parallel jobs"
    echo "  $0 -d -v labs_to_be_deployed              # Dry run with verbose output"
    echo "  $0 --credentials creds.yml labs_to_be_deployed  # Use credentials file"
}

# Function to check prerequisites (JUMPHOST)
check_prerequisites() {
    print_status "Checking prerequisites on JUMPHOST..."
    
    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed on jumphost. Please install Python 3."
        exit 1
    fi
    
    # Check if sshpass is available for automated SSH
    if ! command -v sshpass &> /dev/null; then
        print_warning "sshpass not available. You may need to manually enter SSH passwords."
    fi
    
    # Check if parser script exists
    if [[ ! -f "$PARSER_SCRIPT" ]]; then
        print_error "Parser script not found: $PARSER_SCRIPT"
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
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
        # Escape special characters for JSON/YAML
        escaped_value = value.replace('\\', '\\\\').replace('"', '\\"')
        # Handle both JSON and YAML formats
        patterns = [
            f'{key}: "[^"]*"',  # JSON format
            f"{key}: '[^']*'",  # YAML single quotes
            f'{key}: [^\\n]*$'  # YAML unquoted
        ]
        
        for pattern in patterns:
            if re.search(pattern, content, re.MULTILINE):
                if '"' in content and f'{key}:' in content:
                    replacement = f'{key}: "{escaped_value}"'
                elif "'" in content and f'{key}:' in content:
                    replacement = f"{key}: '{escaped_value}'"
                else:
                    replacement = f'{key}: {escaped_value}'
                content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
                updated = True
                break
    
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

# Function to extract connection details from inventory file
extract_bastion_details() {
    local inventory_file="$1"
    local lab_guid="$2"
    
    # Handle both JSON and YAML formats
    local bastion_host bastion_port bastion_password bastion_user
    
    if grep -q '"bastion_hostname"' "$inventory_file"; then
        # JSON format
        bastion_host=$(grep '"bastion_hostname"' "$inventory_file" | sed 's/.*"bastion_hostname": *"\([^"]*\)".*/\1/')
        bastion_port=$(grep '"bastion_port"' "$inventory_file" | sed 's/.*"bastion_port": *"\([^"]*\)".*/\1/')
        bastion_password=$(grep '"bastion_password"' "$inventory_file" | sed 's/.*"bastion_password": *"\([^"]*\)".*/\1/')
        bastion_user=$(grep '"bastion_user"' "$inventory_file" | sed 's/.*"bastion_user": *"\([^"]*\)".*/\1/')
    else
        # YAML format
        bastion_host=$(grep "bastion_hostname:" "$inventory_file" | sed "s/.*bastion_hostname: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
        bastion_port=$(grep "bastion_port:" "$inventory_file" | sed "s/.*bastion_port: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
        bastion_password=$(grep "bastion_password:" "$inventory_file" | sed "s/.*bastion_password: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
        bastion_user=$(grep "bastion_user:" "$inventory_file" | sed "s/.*bastion_user: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/")
    fi
    
    [[ -z "$bastion_user" ]] && bastion_user="lab-user"
    
    echo "$bastion_host:$bastion_port:$bastion_user:$bastion_password"
}

# Function to check individual inventory configuration
check_inventory_file() {
    local inventory_file="$1"
    local lab_guid="$2"
    
    print_status "Checking inventory configuration for lab: $lab_guid"
    
    # Check for 'changeme' values
    if grep -q "changeme" "$inventory_file"; then
        print_error "Inventory file for lab $lab_guid contains default 'changeme' values."
        return 1
    fi
    
    # Extract connection details
    local connection_details=$(extract_bastion_details "$inventory_file" "$lab_guid")
    local bastion_host=$(echo "$connection_details" | cut -d: -f1)
    local bastion_port=$(echo "$connection_details" | cut -d: -f2)
    local bastion_user=$(echo "$connection_details" | cut -d: -f3)
    
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
        fi
    fi
    
    print_status "Lab $lab_guid: Inventory configuration looks good!"
    print_status "Lab $lab_guid: Bastion: ${bastion_user}@${bastion_host}:${bastion_port}"
    return 0
}

# Function to validate inventory files
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

# Function to setup deployment environment on bastion host
setup_bastion_environment() {
    local bastion_host="$1"
    local bastion_port="$2"
    local bastion_user="$3"
    local bastion_password="$4"
    local lab_guid="$5"
    
    print_lab "[$lab_guid] Setting up deployment environment on bastion..."
    
    # Create the deployment directory structure on bastion
    local setup_commands="
        # Create deployment directory
        mkdir -p /home/$bastion_user/rhoso-deployment/ansible-playbooks
        mkdir -p /home/$bastion_user/rhoso-deployment/logs
        
        # Install required packages if not present
        if ! command -v ansible &> /dev/null; then
            echo 'Ansible not found, attempting to install...'
            if command -v dnf &> /dev/null; then
                sudo dnf install -y ansible python3-pip || echo 'Failed to install via dnf'
            elif command -v yum &> /dev/null; then
                sudo yum install -y ansible python3-pip || echo 'Failed to install via yum'
            fi
        fi
        
        # Ensure kubernetes library is available
        python3 -c 'import kubernetes' 2>/dev/null || {
            echo 'Installing kubernetes library...'
            python3 -m pip install --user kubernetes openshift
        }
        
        echo 'Environment setup completed'
    "
    
    # Execute setup commands on bastion
    if command -v sshpass &> /dev/null; then
        sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$setup_commands"
    else
        print_warning "[$lab_guid] sshpass not available. You may need to enter password manually."
        ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$setup_commands"
    fi
}

# Function to copy deployment files to bastion host
copy_deployment_files() {
    local bastion_host="$1"
    local bastion_port="$2"
    local bastion_user="$3"
    local bastion_password="$4"
    local lab_guid="$5"
    local inventory_file="$6"
    
    print_lab "[$lab_guid] Copying deployment files to bastion..."
    
    # Copy ansible playbooks and inventory to bastion
    local temp_dir="/tmp/rhoso-deploy-$lab_guid"
    mkdir -p "$temp_dir"
    
    # Copy necessary files to temp directory
    cp -r "$ANSIBLE_DIR"/* "$temp_dir/"
    cp "$inventory_file" "$temp_dir/inventory/hosts.yml"
    
    # Copy files to bastion using scp
    if command -v sshpass &> /dev/null; then
        sshpass -p "$bastion_password" scp -o StrictHostKeyChecking=no -P "$bastion_port" -r "$temp_dir"/* "$bastion_user@$bastion_host:/home/$bastion_user/rhoso-deployment/ansible-playbooks/"
    else
        print_warning "[$lab_guid] sshpass not available. You may need to enter password manually."
        scp -o StrictHostKeyChecking=no -P "$bastion_port" -r "$temp_dir"/* "$bastion_user@$bastion_host:/home/$bastion_user/rhoso-deployment/ansible-playbooks/"
    fi
    
    # Clean up temp directory
    rm -rf "$temp_dir"
}

# Function to deploy a single lab (BASTION EXECUTION MODEL)
deploy_lab() {
    local inventory_file="$1"
    local lab_guid="$2"
    local phase="$3"
    local dry_run="$4"
    local verbose="$5"
    
    local log_file="$LOG_DIR/deploy_${lab_guid}_$(date +%Y%m%d_%H%M%S).log"
    
    print_lab "Starting deployment for lab: $lab_guid"
    print_lab "Log file: $log_file"
    
    # Extract bastion connection details
    local connection_details=$(extract_bastion_details "$inventory_file" "$lab_guid")
    local bastion_host=$(echo "$connection_details" | cut -d: -f1)
    local bastion_port=$(echo "$connection_details" | cut -d: -f2)
    local bastion_user=$(echo "$connection_details" | cut -d: -f3)
    local bastion_password=$(echo "$connection_details" | cut -d: -f4)
    
    print_lab "[$lab_guid] Connecting to bastion: ${bastion_user}@${bastion_host}:${bastion_port}"
    
    # Setup environment on bastion
    if ! setup_bastion_environment "$bastion_host" "$bastion_port" "$bastion_user" "$bastion_password" "$lab_guid" >> "$log_file" 2>&1; then
        print_lab "[$lab_guid] ❌ Failed to setup environment on bastion"
        return 1
    fi
    
    # Copy deployment files to bastion
    if ! copy_deployment_files "$bastion_host" "$bastion_port" "$bastion_user" "$bastion_password" "$lab_guid" "$inventory_file" >> "$log_file" 2>&1; then
        print_lab "[$lab_guid] ❌ Failed to copy deployment files to bastion"
        return 1
    fi
    
    # Prepare ansible options
    local ansible_opts=""
    if [[ "$dry_run" == "true" ]]; then
        ansible_opts="--check --diff"
    fi
    
    if [[ "$verbose" == "true" ]]; then
        ansible_opts="$ansible_opts -vv"
    fi
    
    # Prepare deployment command to run on bastion
    local deployment_cmd="
        cd /home/$bastion_user/rhoso-deployment/ansible-playbooks
        
        # Install required collections
        ansible-galaxy collection install -r requirements.yml --force
        
        # Run the deployment
        case '$phase' in
            'prerequisites')
                ansible-playbook site.yml --tags prerequisites $ansible_opts
                ;;
            'install-operators')
                ansible-playbook site.yml --tags install-operators $ansible_opts
                ;;
            'security')
                ansible-playbook site.yml --tags security $ansible_opts
                ;;
            'nfs-server')
                ansible-playbook site.yml --tags nfs-server $ansible_opts
                ;;
            'network-isolation')
                ansible-playbook site.yml --tags network-isolation $ansible_opts
                ;;
            'control-plane')
                ansible-playbook site.yml --tags control-plane $ansible_opts
                ;;
            'data-plane')
                ansible-playbook site.yml --tags data-plane $ansible_opts
                ;;
            'validation')
                ansible-playbook site.yml --tags validation $ansible_opts
                ;;
            'full')
                ansible-playbook site.yml $ansible_opts
                ;;
            'optional')
                ansible-playbook optional-services.yml $ansible_opts
                ;;
            *)
                echo 'Unknown phase: $phase'
                exit 1
                ;;
        esac
    "
    
    # Execute deployment on bastion
    local start_time=$(date +%s)
    print_lab "[$lab_guid] Starting $phase deployment on bastion..."
    
    local ssh_cmd
    if command -v sshpass &> /dev/null; then
        ssh_cmd="sshpass -p '$bastion_password' ssh -o StrictHostKeyChecking=no -p '$bastion_port' '$bastion_user@$bastion_host'"
    else
        ssh_cmd="ssh -o StrictHostKeyChecking=no -p '$bastion_port' '$bastion_user@$bastion_host'"
    fi
    
    if eval "$ssh_cmd '$deployment_cmd'" >> "$log_file" 2>&1; then
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
    print_status "Using BASTION EXECUTION MODEL: Jumphost → SSH to each Bastion → Run locally"
    
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
    
    print_header "Multi-Lab RHOSO Deployment (Bastion Execution Model)"
    print_status "Timestamp: $(date)"
    print_status "Configuration file: $config_file"
    print_status "Deployment phase: $DEPLOYMENT_PHASE"
    print_status "Max parallel jobs: $MAX_PARALLEL_JOBS"
    print_status "Dry run: $DRY_RUN"
    print_status "Verbose: $VERBOSE"
    print_status "Architecture: Jumphost → SSH to each Bastion → Run deployment locally"
    
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
    
    # Validate inventories
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
    
    # Deploy all labs using bastion execution model
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
