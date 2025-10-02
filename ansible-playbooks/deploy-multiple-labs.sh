#!/bin/bash
# Multi-Lab RHOSO Deployment Script
# Deploys multiple RHOSO labs in parallel using bastion host connectivity
# Based on the logic from deploy-via-jumphost.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_BASE_DIR="/tmp/rhoso-multi-deploy-$$"
CREDENTIALS_FILE=""
LABS_CONFIG_FILE=""
MAX_PARALLEL_JOBS=3
DEPLOYMENT_PHASE="full"
DRY_RUN="false"
VERBOSE="false"

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

print_lab_status() {
    local lab_id="$1"
    local message="$2"
    echo -e "${CYAN}[LAB-$lab_id]${NC} $message"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] --labs LABS_FILE --credentials CREDS_FILE [PHASE]"
    echo ""
    echo "Deploy multiple RHOSO labs in parallel using bastion host connectivity."
    echo ""
    echo "Required Options:"
    echo "  --labs FILE            Lab configuration file (format like labs_to_be_deployed)"
    echo "  --credentials FILE     Credentials file (YAML format)"
    echo ""
    echo "Optional Options:"
    echo "  -h, --help            Show this help message"
    echo "  -d, --dry-run         Run in check mode (no changes)"
    echo "  -v, --verbose         Enable verbose output"
    echo "  -j, --jobs N          Maximum parallel jobs (default: 3)"
    echo ""
    echo "Available phases:"
    echo "  prerequisites         Install required operators (NMState, MetalLB)"
    echo "  install-operators     Install OpenStack operators"
    echo "  security             Configure secrets and security"
    echo "  nfs-server           Configure NFS server"
    echo "  network-isolation    Set up network isolation"
    echo "  control-plane        Deploy OpenStack control plane"
    echo "  data-plane           Configure compute nodes"
    echo "  validation           Verify deployment"
    echo "  full                 Run complete deployment (default)"
    echo "  optional             Enable optional services (Heat, Swift)"
    echo ""
    echo "Examples:"
    echo "  $0 --labs labs_to_be_deployed --credentials my_credentials.yml"
    echo "  $0 --labs labs_to_be_deployed --credentials my_credentials.yml --dry-run"
    echo "  $0 --labs labs_to_be_deployed --credentials my_credentials.yml -j 5 control-plane"
    echo ""
    echo "Lab Configuration File Format:"
    echo "  The script expects a file with lab entries separated by service names."
    echo "  Each lab should have a 'Data' section with YAML-like configuration."
    echo ""
    echo "Credentials File Format:"
    echo "  registry_username: \"12345678|myserviceaccount\""
    echo "  registry_password: \"eyJhbGciOiJSUzUxMiJ9...\""
    echo "  rhc_username: \"your-rh-username@email.com\""
    echo "  rhc_password: \"YourRHPassword123\""
}

# Function to parse credentials file
parse_credentials_file() {
    local credentials_file="$1"
    
    if [[ ! -f "$credentials_file" ]]; then
        print_error "Credentials file not found: $credentials_file"
        exit 1
    fi
    
    print_status "Loading credentials from: $credentials_file"
    
    # Parse YAML credentials file and export as environment variables
    export CRED_REGISTRY_USERNAME=$(grep "^registry_username:" "$credentials_file" | sed 's/registry_username: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    export CRED_REGISTRY_PASSWORD=$(grep "^registry_password:" "$credentials_file" | sed 's/registry_password: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    export CRED_RHC_USERNAME=$(grep "^rhc_username:" "$credentials_file" | sed 's/rhc_username: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    export CRED_RHC_PASSWORD=$(grep "^rhc_password:" "$credentials_file" | sed 's/rhc_password: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    
    # Validate that required credentials were found
    if [[ -z "$CRED_REGISTRY_USERNAME" || -z "$CRED_REGISTRY_PASSWORD" || -z "$CRED_RHC_USERNAME" || -z "$CRED_RHC_PASSWORD" ]]; then
        print_error "Missing required credentials in file: $credentials_file"
        echo "Required fields: registry_username, registry_password, rhc_username, rhc_password"
        exit 1
    fi
    
    print_status "Credentials loaded successfully"
    print_status "Registry username: ${CRED_REGISTRY_USERNAME%%|*}|***"
    print_status "RHC username: $CRED_RHC_USERNAME"
}

# Function to parse lab configuration file
parse_lab_config() {
    local config_file="$1"
    local temp_dir="$2"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Lab configuration file not found: $config_file"
        exit 1
    fi
    
    print_status "Parsing lab configuration from: $config_file"
    
    # Create directory for parsed lab configs
    mkdir -p "$temp_dir/lab_configs"
    
    # Parse the lab configuration file
    # The format has service names followed by data sections
    local lab_count=0
    local current_lab=""
    local in_data_section=false
    local lab_config_file=""
    
    while IFS= read -r line; do
        # Skip empty lines and headers
        if [[ -z "$line" || "$line" =~ ^(Service|Lab\ UI|Messages|RHOSO\ External|Allocation|Network|Allocated|Environment|Authentication|User|OpenShift|Enter|Data).*$ ]]; then
            if [[ "$line" == "Data" ]]; then
                in_data_section=true
            fi
            continue
        fi
        
        # Check for service name (lab identifier)
        if [[ "$line" =~ ^openshift-cnv\.osp-on-ocp-cnv\.([^[:space:]]+) ]]; then
            # Save previous lab if exists
            if [[ -n "$current_lab" && -n "$lab_config_file" ]]; then
                echo ")" >> "$lab_config_file"
                ((lab_count++))
            fi
            
            # Start new lab - clean up the lab ID
            current_lab="${BASH_REMATCH[1]}"
            # Remove any trailing characters and clean up
            current_lab=$(echo "$current_lab" | sed 's/[[:space:]]*$//' | sed 's/[^a-zA-Z0-9-]//g')
            
            # Skip if this is just "prod" (data section header)
            if [[ "$current_lab" == "prod" ]]; then
                in_data_section=true
                continue
            fi
            
            lab_config_file="$temp_dir/lab_configs/lab_${current_lab}.conf"
            in_data_section=false
            
            print_status "Found lab: $current_lab"
            echo "LAB_ID=\"$current_lab\"" > "$lab_config_file"
            echo "declare -A LAB_CONFIG=(" >> "$lab_config_file"
            continue
        fi
        
        # Parse SSH connection info from text
        if [[ "$line" =~ ssh\ lab-user@([^[:space:]]+)\ -p\ ([0-9]+) ]]; then
            local bastion_host="${BASH_REMATCH[1]}"
            local bastion_port="${BASH_REMATCH[2]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"bastion_hostname\"]=\"$bastion_host\"" >> "$lab_config_file"
                echo "  [\"bastion_port\"]=\"$bastion_port\"" >> "$lab_config_file"
                echo "  [\"bastion_user\"]=\"lab-user\"" >> "$lab_config_file"
            fi
            continue
        fi
        
        # Parse SSH password
        if [[ "$line" =~ Enter\ ssh\ password\ when\ prompted:\ ([^[:space:]]+) ]]; then
            local bastion_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"bastion_password\"]=\"$bastion_password\"" >> "$lab_config_file"
            fi
            continue
        fi
        
        # Parse admin password
        if [[ "$line" =~ User\ admin\ with\ password\ ([^[:space:]]+)\ is\ cluster\ admin ]]; then
            local admin_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"ocp_admin_password\"]=\"$admin_password\"" >> "$lab_config_file"
            fi
            continue
        fi
        
        # Parse OpenShift console URL
        if [[ "$line" =~ OpenShift\ Console:\ (https://[^[:space:]]+) ]]; then
            local console_url="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"ocp_console_url\"]=\"$console_url\"" >> "$lab_config_file"
            fi
            continue
        fi
        
        # Parse data section (YAML-like format)
        if [[ "$in_data_section" == "true" && "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]// /_}"  # Replace spaces with underscores
            local value="${BASH_REMATCH[2]}"
            
            # Clean up the value (remove quotes, handle multiline)
            value=$(echo "$value" | sed 's/^["\x27]\|["\x27]$//g' | sed 's/^[[:space:]]*\|[[:space:]]*$//g')
            
            # Skip empty values and multiline indicators
            if [[ -n "$lab_config_file" && -n "$value" && "$value" != ">" ]]; then
                echo "  [\"$key\"]=\"$value\"" >> "$lab_config_file"
            fi
            continue
        fi
        
        # Parse external IP variables
        if [[ "$line" =~ EXTERNAL_IP_([^=]+)=(.+) ]]; then
            local ip_type="${BASH_REMATCH[1],,}"  # Convert to lowercase
            local ip_value="${BASH_REMATCH[2]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"rhoso_external_ip_${ip_type}\"]=\"$ip_value\"" >> "$lab_config_file"
            fi
            continue
        fi
        
    done < "$config_file"
    
    # Close the last lab config
    if [[ -n "$current_lab" && -n "$lab_config_file" ]]; then
        echo ")" >> "$lab_config_file"
        ((lab_count++))
    fi
    
    print_status "Parsed $lab_count labs from configuration file"
    return $lab_count
}

# Function to create inventory file for a lab
create_lab_inventory() {
    local lab_config_file="$1"
    local lab_temp_dir="$2"
    
    # Source the lab configuration
    source "$lab_config_file"
    
    # Create inventory directory
    mkdir -p "$lab_temp_dir/inventory"
    
    # Create inventory file based on template
    cat > "$lab_temp_dir/inventory/hosts.yml" << EOF
---
# Ansible inventory for RHOSO deployment via SSH jump host (bastion)
# Auto-generated for lab: $LAB_ID

all:
  vars:
    # Lab-specific variables
    lab_guid: "${LAB_CONFIG[guid]:-$LAB_ID}"
    bastion_user: "${LAB_CONFIG[bastion_user]:-lab-user}"
    bastion_hostname: "${LAB_CONFIG[bastion_hostname]:-${LAB_CONFIG[bastion_public_hostname]:-}}"
    bastion_port: "${LAB_CONFIG[bastion_port]:-${LAB_CONFIG[bastion_ssh_port]:-22}}"
    bastion_password: "${LAB_CONFIG[bastion_password]:-${LAB_CONFIG[bastion_ssh_password]:-}}"
    
    # OpenShift Console URL and credentials  
    ocp_console_url: "${LAB_CONFIG[ocp_console_url]:-${LAB_CONFIG[openshift_console_url]:-}}"
    ocp_admin_password: "${LAB_CONFIG[ocp_admin_password]:-${LAB_CONFIG[openshift_cluster_admin_password]:-}}"
    
    # Red Hat Registry credentials (injected from credentials file)
    registry_username: "$CRED_REGISTRY_USERNAME"
    registry_password: "$CRED_REGISTRY_PASSWORD"
    
    # Subscription Manager credentials (injected from credentials file)
    rhc_username: "$CRED_RHC_USERNAME"
    rhc_password: "$CRED_RHC_PASSWORD"
    
    # Internal lab hostnames (accessed from bastion)
    nfs_server_hostname: "nfsserver"
    compute_hostname: "compute01"
    
    # External IP configuration for OpenShift worker nodes
    rhoso_external_ip_worker_1: "${LAB_CONFIG[rhoso_external_ip_worker_1]:-172.21.0.21}"
    rhoso_external_ip_worker_2: "${LAB_CONFIG[rhoso_external_ip_worker_2]:-172.21.0.22}"
    rhoso_external_ip_worker_3: "${LAB_CONFIG[rhoso_external_ip_worker_3]:-172.21.0.23}"
    
    # Bastion external IP for final network configuration
    rhoso_external_ip_bastion: "${LAB_CONFIG[rhoso_external_ip_bastion]:-172.21.0.50}"

# All operations run on the bastion host
bastion:
  hosts:
    bastion-jumphost:
      ansible_host: "\{{ bastion_hostname }}"
      ansible_user: "\{{ bastion_user }}"
      ansible_port: "\{{ bastion_port }}"
      ansible_ssh_pass: "\{{ bastion_password }}"
      ansible_python_interpreter: /usr/bin/python3.11

# NFS server operations via SSH jump host (bastion)
nfsserver:
  hosts:
    nfs-server:
      ansible_host: "\{{ nfs_server_hostname }}"
      ansible_user: "cloud-user"
      ansible_ssh_private_key_file: "/home/\{{ bastion_user }}/.ssh/\{{ lab_guid }}key.pem"
      # SSH through bastion host
      ansible_ssh_common_args: '-o ProxyCommand="sshpass -p \{{ bastion_password }} ssh -W %h:%p -p \{{ bastion_port }} \{{ bastion_user }}@\{{ bastion_hostname }}"'

# Compute node operations via SSH jump host (bastion)
compute_nodes:
  hosts:
    compute01:
      ansible_host: "\{{ compute_hostname }}"
      ansible_user: "cloud-user"
      ansible_ssh_private_key_file: "/home/\{{ bastion_user }}/.ssh/\{{ lab_guid }}key.pem"
      # SSH through bastion host
      ansible_ssh_common_args: '-o ProxyCommand="sshpass -p \{{ bastion_password }} ssh -W %h:%p -p \{{ bastion_port }} \{{ bastion_user }}@\{{ bastion_hostname }}"'
EOF
    
    print_lab_status "$LAB_ID" "Created inventory file"
}

# Function to deploy a single lab
deploy_single_lab() {
    local lab_config_file="$1"
    local lab_temp_dir="$2"
    local phase="$3"
    local dry_run="$4"
    local verbose="$5"
    
    # Source the lab configuration
    source "$lab_config_file"
    
    print_lab_status "$LAB_ID" "Starting deployment (phase: $phase)"
    
    # Create log file for this lab
    local log_file="$lab_temp_dir/deployment.log"
    exec 3>&1 4>&2
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    # Extract bastion connection details
    local bastion_host="${LAB_CONFIG[bastion_hostname]:-${LAB_CONFIG[bastion_public_hostname]:-}}"
    local bastion_port="${LAB_CONFIG[bastion_port]:-${LAB_CONFIG[bastion_ssh_port]:-22}}"
    local bastion_user="${LAB_CONFIG[bastion_user]:-lab-user}"
    local bastion_password="${LAB_CONFIG[bastion_password]:-${LAB_CONFIG[bastion_ssh_password]:-}}"
    
    print_lab_status "$LAB_ID" "Bastion: ${bastion_user}@${bastion_host}:${bastion_port}"
    
    # Setup deployment environment on bastion
    local setup_commands="
        mkdir -p /home/$bastion_user/rhoso-deployment
        
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
    
    # Execute setup commands on bastion
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" ]]; then
        sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$setup_commands" || {
            print_lab_status "$LAB_ID" "Failed to setup environment on bastion"
            exec 1>&3 2>&4
            return 1
        }
    else
        print_lab_status "$LAB_ID" "sshpass not available, manual password entry may be required"
        ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$setup_commands" || {
            print_lab_status "$LAB_ID" "Failed to setup environment on bastion"
            exec 1>&3 2>&4
            return 1
        }
    fi
    
    # Copy deployment files to bastion
    print_lab_status "$LAB_ID" "Copying deployment files to bastion..."
    
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" ]]; then
        sshpass -p "$bastion_password" scp -o StrictHostKeyChecking=no -P "$bastion_port" -r "$lab_temp_dir"/* "$bastion_user@$bastion_host:/home/$bastion_user/rhoso-deployment/" || {
            print_lab_status "$LAB_ID" "Failed to copy files to bastion"
            exec 1>&3 2>&4
            return 1
        }
    else
        scp -o StrictHostKeyChecking=no -P "$bastion_port" -r "$lab_temp_dir"/* "$bastion_user@$bastion_host:/home/$bastion_user/rhoso-deployment/" || {
            print_lab_status "$LAB_ID" "Failed to copy files to bastion"
            exec 1>&3 2>&4
            return 1
        }
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
    print_lab_status "$LAB_ID" "Running deployment on bastion..."
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" ]]; then
        sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$deployment_cmd" || {
            print_lab_status "$LAB_ID" "Deployment failed"
            exec 1>&3 2>&4
            return 1
        }
    else
        ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$deployment_cmd" || {
            print_lab_status "$LAB_ID" "Deployment failed"
            exec 1>&3 2>&4
            return 1
        }
    fi
    
    # Restore stdout/stderr
    exec 1>&3 2>&4
    
    print_lab_status "$LAB_ID" "Deployment completed successfully"
    return 0
}

# Function to deploy all labs in parallel
deploy_all_labs() {
    local temp_dir="$1"
    local phase="$2"
    local dry_run="$3"
    local verbose="$4"
    
    print_header "Starting parallel deployment of all labs"
    print_status "Phase: $phase"
    print_status "Max parallel jobs: $MAX_PARALLEL_JOBS"
    
    # Create job control arrays
    declare -a job_pids=()
    declare -a job_labs=()
    local active_jobs=0
    
    # Process each lab configuration
    for lab_config in "$temp_dir/lab_configs"/*.conf; do
        if [[ ! -f "$lab_config" ]]; then
            continue
        fi
        
        # Wait if we've reached max parallel jobs
        while [[ $active_jobs -ge $MAX_PARALLEL_JOBS ]]; do
            # Check for completed jobs
            for i in "${!job_pids[@]}"; do
                if ! kill -0 "${job_pids[$i]}" 2>/dev/null; then
                    # Job completed
                    wait "${job_pids[$i]}"
                    local exit_code=$?
                    if [[ $exit_code -eq 0 ]]; then
                        print_lab_status "${job_labs[$i]}" "Completed successfully"
                    else
                        print_lab_status "${job_labs[$i]}" "Failed with exit code $exit_code"
                    fi
                    
                    # Remove from arrays
                    unset job_pids[$i]
                    unset job_labs[$i]
                    ((active_jobs--))
                fi
            done
            
            # Compact arrays
            job_pids=("${job_pids[@]}")
            job_labs=("${job_labs[@]}")
            
            sleep 2
        done
        
        # Source lab config to get LAB_ID
        source "$lab_config"
        local lab_id="$LAB_ID"
        
        # Create lab-specific temp directory
        local lab_temp_dir="$temp_dir/lab_$lab_id"
        mkdir -p "$lab_temp_dir"
        
        # Copy ansible-playbooks and content to lab temp dir
        cp -r "$SCRIPT_DIR"/../ansible-playbooks "$lab_temp_dir/"
        cp -r "$SCRIPT_DIR"/../content "$lab_temp_dir/"
        
        # Create inventory for this lab
        create_lab_inventory "$lab_config" "$lab_temp_dir"
        
        # Start deployment in background
        print_lab_status "$lab_id" "Starting deployment in background"
        deploy_single_lab "$lab_config" "$lab_temp_dir" "$phase" "$dry_run" "$verbose" &
        local job_pid=$!
        
        # Track the job
        job_pids+=($job_pid)
        job_labs+=("$lab_id")
        ((active_jobs++))
        
        print_lab_status "$lab_id" "Started (PID: $job_pid)"
    done
    
    # Wait for all remaining jobs to complete
    print_status "Waiting for all deployments to complete..."
    for i in "${!job_pids[@]}"; do
        wait "${job_pids[$i]}"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            print_lab_status "${job_labs[$i]}" "Completed successfully"
        else
            print_lab_status "${job_labs[$i]}" "Failed with exit code $exit_code"
        fi
    done
    
    print_header "All lab deployments completed"
}

# Main execution
main() {
    local phase="full"
    local dry_run="false"
    local verbose="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --labs)
                if [[ -n "${2:-}" ]]; then
                    LABS_CONFIG_FILE="$2"
                    shift 2
                else
                    print_error "--labs requires a file path"
                    show_usage
                    exit 1
                fi
                ;;
            --credentials)
                if [[ -n "${2:-}" ]]; then
                    CREDENTIALS_FILE="$2"
                    shift 2
                else
                    print_error "--credentials requires a file path"
                    show_usage
                    exit 1
                fi
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -j|--jobs)
                if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                    MAX_PARALLEL_JOBS="$2"
                    shift 2
                else
                    print_error "--jobs requires a numeric value"
                    show_usage
                    exit 1
                fi
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
    
    # Validate required arguments
    if [[ -z "$LABS_CONFIG_FILE" || -z "$CREDENTIALS_FILE" ]]; then
        print_error "Both --labs and --credentials are required"
        show_usage
        exit 1
    fi
    
    print_header "Multi-Lab RHOSO Deployment - Phase: $phase"
    print_status "Timestamp: $(date)"
    print_status "Labs config: $LABS_CONFIG_FILE"
    print_status "Credentials: $CREDENTIALS_FILE"
    print_status "Max parallel jobs: $MAX_PARALLEL_JOBS"
    
    # Parse credentials file
    parse_credentials_file "$CREDENTIALS_FILE"
    
    # Create temporary directory
    mkdir -p "$TEMP_BASE_DIR"
    
    # Cleanup function
    cleanup() {
        print_status "Cleaning up temporary files..."
        rm -rf "$TEMP_BASE_DIR"
    }
    trap cleanup EXIT
    
    # Parse lab configuration
    parse_lab_config "$LABS_CONFIG_FILE" "$TEMP_BASE_DIR"
    local lab_count=$?
    
    if [[ $lab_count -eq 0 ]]; then
        print_error "No labs found in configuration file"
        exit 1
    fi
    
    # Deploy all labs
    deploy_all_labs "$TEMP_BASE_DIR" "$phase" "$dry_run" "$verbose"
    
    if [[ "$dry_run" == "true" ]]; then
        print_status "Dry run completed successfully for $lab_count labs!"
    else
        print_status "Deployment completed successfully for $lab_count labs!"
    fi
    
    print_status "Log files are available in: $TEMP_BASE_DIR/lab_*/deployment.log"
}

# Run main function with all arguments
main "$@"
