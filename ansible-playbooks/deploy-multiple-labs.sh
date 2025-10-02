#!/bin/bash

# Multi-Lab RHOSO Deployment Script
# This script deploys multiple RHOSO labs in parallel using deploy-via-jumphost.sh

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_DIR="logs"
MULTI_LAB_LOG_FILE=""
DEPLOYMENT_START_TIME=""

# Initialize multi-lab logging
init_multi_lab_logging() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    # Create logs directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Set log file name
    MULTI_LAB_LOG_FILE="$LOG_DIR/multi_lab_deployment_${timestamp}.log"
    DEPLOYMENT_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log file with header
    cat > "$MULTI_LAB_LOG_FILE" << EOF
================================================================================
Multi-Lab RHOSO Deployment Log
================================================================================
Start Time: $DEPLOYMENT_START_TIME
Host: $(hostname)
User: $(whoami)
Working Directory: $(pwd)
Script: $0
Arguments: $*
================================================================================

EOF
    
    echo "Multi-lab logging to: $MULTI_LAB_LOG_FILE"
}

# Function to log message to multi-lab file
log_multi_lab_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "$MULTI_LAB_LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$MULTI_LAB_LOG_FILE"
    fi
}

# Print functions
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    log_multi_lab_message "ERROR" "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_multi_lab_message "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_multi_lab_message "WARNING" "$1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_multi_lab_message "INFO" "$1"
}

print_status() {
    echo -e "${GREEN}[STATUS]${NC} $1"
    log_multi_lab_message "STATUS" "$1"
}

# Function to finalize multi-lab deployment log
finalize_multi_lab_log() {
    local total_labs="$1"
    local success_count="$2"
    local failure_count="$3"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "$MULTI_LAB_LOG_FILE" ]]; then
        cat >> "$MULTI_LAB_LOG_FILE" << EOF

================================================================================
Multi-Lab Deployment Summary
================================================================================
Start Time: $DEPLOYMENT_START_TIME
End Time: $end_time
Duration: $(($(date -d "$end_time" +%s) - $(date -d "$DEPLOYMENT_START_TIME" +%s))) seconds
Total Labs: $total_labs
Successful Deployments: $success_count
Failed Deployments: $failure_count
Success Rate: $(( success_count * 100 / total_labs ))%
Overall Status: $([ "$failure_count" -eq 0 ] && echo "SUCCESS" || echo "PARTIAL_SUCCESS")
Log File: $MULTI_LAB_LOG_FILE
================================================================================

Individual Lab Logs:
EOF
        
        # List individual lab log files
        for log_file in "$LOG_DIR"/deployment_*_*.log; do
            if [[ -f "$log_file" && "$log_file" != "$MULTI_LAB_LOG_FILE" ]]; then
                echo "  - $(basename "$log_file")" >> "$MULTI_LAB_LOG_FILE"
            fi
        done
        
        echo "" >> "$MULTI_LAB_LOG_FILE"
        echo "================================================================================" >> "$MULTI_LAB_LOG_FILE"
        
        print_status "Multi-lab deployment log saved to: $MULTI_LAB_LOG_FILE"
    fi
}

# Usage function
usage() {
    cat << EOF
Usage: $0 --labs <labs_file> --credentials <credentials_file> [OPTIONS]

Deploy multiple RHOSO labs in parallel.

Required Arguments:
  --labs <file>         Path to the labs configuration file
  --credentials <file>  Path to the credentials YAML file

Optional Arguments:
  --max-parallel <num>  Maximum number of parallel deployments (default: 3)
  --dry-run            Show what would be deployed without actually deploying
  --help               Show this help message

Examples:
  $0 --labs labs_to_be_deployed --credentials my_credentials.yml
  $0 --labs labs_to_be_deployed --credentials my_credentials.yml --max-parallel 2
  $0 --labs labs_to_be_deployed --credentials my_credentials.yml --dry-run

Lab Configuration File Format:
  The labs file should contain lab information in the format provided by
  the lab provisioning system. See labs_to_be_deployed.example for reference.

Credentials File Format:
  The credentials file should be in YAML format. See credentials.yml.example
  for the required fields.
EOF
}

# Parse command line arguments
parse_arguments() {
    LABS_FILE=""
    CREDENTIALS_FILE=""
    MAX_PARALLEL=3
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --labs)
                LABS_FILE="$2"
                shift 2
                ;;
            --credentials)
                CREDENTIALS_FILE="$2"
                shift 2
                ;;
            --max-parallel)
                MAX_PARALLEL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$LABS_FILE" ]]; then
        print_error "Labs file is required. Use --labs <file>"
        usage
        exit 1
    fi

    if [[ -z "$CREDENTIALS_FILE" ]]; then
        print_error "Credentials file is required. Use --credentials <file>"
        usage
        exit 1
    fi

    # Validate files exist
    if [[ ! -f "$LABS_FILE" ]]; then
        print_error "Labs file not found: $LABS_FILE"
        exit 1
    fi

    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        print_error "Credentials file not found: $CREDENTIALS_FILE"
        exit 1
    fi

    # Validate max parallel is a number
    if ! [[ "$MAX_PARALLEL" =~ ^[0-9]+$ ]] || [[ "$MAX_PARALLEL" -lt 1 ]]; then
        print_error "Max parallel must be a positive integer"
        exit 1
    fi
}

# Parse lab configuration file
parse_lab_config() {
    local config_file="$1"
    local temp_dir="$2"
    local lab_count=0
    local current_lab=""
    local lab_config_file=""
    local in_data_section=false
    local skip_next_line=false

    mkdir -p "$temp_dir/lab_configs"

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip if we're supposed to skip this line (for multi-line YAML)
        if [[ "$skip_next_line" == "true" ]]; then
            skip_next_line=false
            continue
        fi

        # Check for "Data" section header
        if [[ "$line" =~ ^Data ]]; then
            in_data_section=true
            continue
        fi

        # Check for service name (lab identifier)
        if [[ "$line" =~ ^openshift-cnv\.osp-on-ocp-cnv\.([^[:space:]]+) ]]; then
            # Save previous lab if exists and it's valid
            if [[ -n "$current_lab" && -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo ")" >> "$lab_config_file"
                ((lab_count++))
                print_info "Completed parsing lab: $current_lab" >&2
            fi

            # Start new lab - clean up the lab ID
            current_lab="${BASH_REMATCH[1]}"
            current_lab=$(echo "$current_lab" | sed 's/[[:space:]]*$//' | sed 's/[^a-zA-Z0-9-]//g')

            # Skip if this is just "prod" (data section header) or empty
            if [[ "$current_lab" == "prod" || -z "$current_lab" ]]; then
                current_lab=""
                lab_config_file=""
                in_data_section=true
                continue
            fi

            lab_config_file="$temp_dir/lab_configs/lab_${current_lab}.conf"
            in_data_section=false

            print_status "Found lab: $current_lab" >&2
            echo "LAB_ID=\"$current_lab\"" > "$lab_config_file"
            echo "declare -A LAB_CONFIG=(" >> "$lab_config_file"
            continue
        fi

        # Parse SSH connection info from text
        if [[ "$line" =~ ssh\ lab-user@([^[:space:]]+)\ -p\ ([0-9]+) ]]; then
            local bastion_host="${BASH_REMATCH[1]}"
            local bastion_port="${BASH_REMATCH[2]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"bastion_hostname\"]=\"$bastion_host\"" >> "$lab_config_file"
                echo "  [\"bastion_port\"]=\"$bastion_port\"" >> "$lab_config_file"
                echo "  [\"bastion_user\"]=\"lab-user\"" >> "$lab_config_file"
                print_info "  SSH: lab-user@$bastion_host:$bastion_port" >&2
            fi
            continue
        fi

        # Parse SSH password
        if [[ "$line" =~ Enter\ ssh\ password\ when\ prompted:\ ([^[:space:]]+) ]]; then
            local bastion_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"bastion_password\"]=\"$bastion_password\"" >> "$lab_config_file"
                print_info "  Password: ***" >&2
            fi
            continue
        fi

        # Parse admin password
        if [[ "$line" =~ User\ admin\ with\ password\ ([^[:space:]]+)\ is\ cluster\ admin ]]; then
            local admin_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"ocp_admin_password\"]=\"$admin_password\"" >> "$lab_config_file"
                print_info "  Admin Password: ***" >&2
            fi
            continue
        fi

        # Parse OpenShift console URL
        if [[ "$line" =~ OpenShift\ Console:\ (https://[^[:space:]]+) ]]; then
            local console_url="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"ocp_console_url\"]=\"$console_url\"" >> "$lab_config_file"
            fi
            continue
        fi

        # Parse data section (YAML-like format)
        if [[ "$in_data_section" == "true" && "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]// /_}"
            local value="${BASH_REMATCH[2]}"

            # Handle multi-line YAML values (>- syntax)
            if [[ "$value" == ">-" ]]; then
                skip_next_line=true
                continue
            fi

            # Clean up value
            value=$(echo "$value" | sed 's/^["\x27]\|["\x27]$//g' | sed 's/^[[:space:]]*\|[[:space:]]*$//g')

            if [[ -n "$lab_config_file" && -n "$value" && "$value" != ">" && "$current_lab" != "prod" ]]; then
                echo "  [\"$key\"]=\"$value\"" >> "$lab_config_file"
                print_info "  Data: $key = $value" >&2
            fi
            continue
        fi

        # Parse external IP variables (only from export lines to avoid duplicates)
        if [[ "$line" =~ ^export\ EXTERNAL_IP_([^=]+)=(.+) ]]; then
            local ip_type="${BASH_REMATCH[1],,}"
            local ip_value="${BASH_REMATCH[2]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"rhoso_external_ip_${ip_type}\"]=\"$ip_value\"" >> "$lab_config_file"
                print_info "  External IP ${ip_type}: $ip_value" >&2
            fi
            continue
        fi

    done < "$config_file"

    # Save the last lab if it's valid
    if [[ -n "$current_lab" && -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
        echo ")" >> "$lab_config_file"
        ((lab_count++))
        print_info "Completed parsing lab: $current_lab" >&2
    fi

    echo "$lab_count"
}

# Deploy a single lab
deploy_lab() {
    local lab_config_file="$1"
    local credentials_file="$2"
    local lab_id="$3"

    print_status "Starting deployment for lab: $lab_id"
    log_multi_lab_message "LAB_START" "Starting deployment for lab: $lab_id"

    # Source the lab configuration (disable unbound variable check temporarily)
    set +u
    source "$lab_config_file"
    set -u

    # Check if we have required configuration
    if [[ -z "${LAB_CONFIG[bastion_hostname]:-}" || -z "${LAB_CONFIG[bastion_port]:-}" || -z "${LAB_CONFIG[bastion_password]:-}" ]]; then
        print_error "Missing required bastion configuration for lab $lab_id"
        log_multi_lab_message "LAB_ERROR" "Lab $lab_id: Missing required bastion configuration"
        return 1
    fi
    
    # Log lab configuration details
    log_multi_lab_message "LAB_CONFIG" "Lab $lab_id: Bastion ${LAB_CONFIG[bastion_hostname]}:${LAB_CONFIG[bastion_port]}"
    log_multi_lab_message "LAB_CONFIG" "Lab $lab_id: GUID ${LAB_CONFIG[guid]:-$lab_id}"

    # Create a temporary inventory file for this lab
    local temp_inventory=$(mktemp)
    
    # Create lab-specific inventory based on template
    cat > "$temp_inventory" << EOF
---
# Ansible inventory for RHOSO deployment via SSH jump host (bastion)
# Lab-specific inventory for: $lab_id

all:
  vars:
    # Lab-specific variables
    lab_guid: "${LAB_CONFIG[guid]:-$lab_id}"
    bastion_user: "${LAB_CONFIG[bastion_user]:-lab-user}"
    bastion_hostname: "${LAB_CONFIG[bastion_hostname]}"
    bastion_port: "${LAB_CONFIG[bastion_port]}"
    bastion_password: "${LAB_CONFIG[bastion_password]}"
    
    # OpenShift Console URL and credentials  
    ocp_console_url: "${LAB_CONFIG[ocp_console_url]:-https://console.example.com}"
    ocp_admin_password: "${LAB_CONFIG[ocp_admin_password]:-changeme}"
    
    # Red Hat Registry credentials (will be injected by deploy-via-jumphost.sh)
    registry_username: ""
    registry_password: ""
    
    # Subscription Manager credentials (will be injected by deploy-via-jumphost.sh)
    rhc_username: ""
    rhc_password: ""
    
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
      ansible_host: "${LAB_CONFIG[bastion_hostname]}"
      ansible_user: "${LAB_CONFIG[bastion_user]:-lab-user}"
      ansible_port: "${LAB_CONFIG[bastion_port]}"
      ansible_ssh_pass: "${LAB_CONFIG[bastion_password]}"
      ansible_python_interpreter: /usr/bin/python3.11

# NFS server configuration (accessed via bastion)
nfsserver:
  hosts:
    nfs-server:
      ansible_host: "nfsserver"
      ansible_user: "cloud-user"
      ansible_ssh_private_key_file: "/home/${LAB_CONFIG[bastion_user]:-lab-user}/.ssh/${LAB_CONFIG[guid]:-$lab_id}key.pem"
      # SSH through bastion host
      ansible_ssh_common_args: '-o ProxyCommand="sshpass -p ${LAB_CONFIG[bastion_password]} ssh -W %h:%p -p ${LAB_CONFIG[bastion_port]} ${LAB_CONFIG[bastion_user]:-lab-user}@${LAB_CONFIG[bastion_hostname]}"'

# Compute nodes configuration (accessed via bastion)
compute_nodes:
  hosts:
    compute01:
      ansible_host: "compute01"
      ansible_user: "cloud-user"
      ansible_ssh_private_key_file: "/home/${LAB_CONFIG[bastion_user]:-lab-user}/.ssh/${LAB_CONFIG[guid]:-$lab_id}key.pem"
      # SSH through bastion host
      ansible_ssh_common_args: '-o ProxyCommand="sshpass -p ${LAB_CONFIG[bastion_password]} ssh -W %h:%p -p ${LAB_CONFIG[bastion_port]} ${LAB_CONFIG[bastion_user]:-lab-user}@${LAB_CONFIG[bastion_hostname]}"'
EOF

    # Run the deployment using the custom inventory
    print_info "Running deployment for lab $lab_id..."
    log_multi_lab_message "LAB_DEPLOY" "Lab $lab_id: Starting deployment execution"
    
    local lab_start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    if ./deploy-via-jumphost.sh --inventory "$temp_inventory" --credentials "$credentials_file" > "deployment_${lab_id}.log" 2>&1; then
        local lab_end_time=$(date '+%Y-%m-%d %H:%M:%S')
        local lab_duration=$(($(date -d "$lab_end_time" +%s) - $(date -d "$lab_start_time" +%s)))
        
        print_success "Lab $lab_id deployment completed successfully"
        log_multi_lab_message "LAB_SUCCESS" "Lab $lab_id: Deployment completed successfully in ${lab_duration}s"
        log_multi_lab_message "LAB_LOG" "Lab $lab_id: Individual log saved to deployment_${lab_id}.log"
        
        rm -f "$temp_inventory"
        return 0
    else
        local lab_end_time=$(date '+%Y-%m-%d %H:%M:%S')
        local lab_duration=$(($(date -d "$lab_end_time" +%s) - $(date -d "$lab_start_time" +%s)))
        
        print_error "Lab $lab_id deployment failed. Check deployment_${lab_id}.log for details"
        log_multi_lab_message "LAB_FAILURE" "Lab $lab_id: Deployment failed after ${lab_duration}s"
        log_multi_lab_message "LAB_LOG" "Lab $lab_id: Error log saved to deployment_${lab_id}.log"
        
        rm -f "$temp_inventory"
        return 1
    fi
}

# Main function
main() {
    # Initialize logging first
    init_multi_lab_logging "$@"
    
    print_status "Multi-Lab RHOSO Deployment Script"
    print_status "=================================="

    # Parse arguments
    parse_arguments "$@"

    print_info "Labs file: $LABS_FILE"
    print_info "Credentials file: $CREDENTIALS_FILE"
    print_info "Max parallel deployments: $MAX_PARALLEL"
    print_info "Dry run: $DRY_RUN"

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    print_status "Parsing lab configuration..."
    
    # Parse labs - messages go to stderr, count to stdout
    local lab_count
    lab_count=$(parse_lab_config "$LABS_FILE" "$temp_dir")

    if [[ -z "$lab_count" || "$lab_count" -eq 0 ]]; then
        print_error "No valid labs found in configuration file"
        exit 1
    fi

    print_success "Found $lab_count labs to deploy"

    # List the labs found
    print_info "Labs to be deployed:"
    for config_file in "$temp_dir"/lab_configs/lab_*.conf; do
        if [[ -f "$config_file" ]]; then
            local lab_id=$(basename "$config_file" .conf | sed 's/^lab_//')
            print_info "  - $lab_id"
        fi
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "Dry run mode - no actual deployments will be performed"
        
        # Show what would be deployed
        for config_file in "$temp_dir"/lab_configs/lab_*.conf; do
            if [[ -f "$config_file" ]]; then
                local lab_id=$(basename "$config_file" .conf | sed 's/^lab_//')
                print_info "Would deploy lab: $lab_id"
                
                # Source and show key config (disable unbound variable check temporarily)
                set +u
                if source "$config_file" 2>/dev/null; then
                    print_info "  Bastion: ${LAB_CONFIG[bastion_hostname]:-unknown}:${LAB_CONFIG[bastion_port]:-unknown}"
                    print_info "  GUID: ${LAB_CONFIG[guid]:-unknown}"
                else
                    print_warning "  Could not load configuration for $lab_id"
                fi
                set -u
            fi
        done
        
        exit 0
    fi

    # Deploy labs in parallel
    print_status "Starting parallel deployments..."
    local pids=()
    local active_jobs=0

    for config_file in "$temp_dir"/lab_configs/lab_*.conf; do
        if [[ -f "$config_file" ]]; then
            local lab_id=$(basename "$config_file" .conf | sed 's/^lab_//')
            
            # Wait if we've reached max parallel limit
            while [[ "$active_jobs" -ge "$MAX_PARALLEL" ]]; do
                wait -n  # Wait for any job to complete
                ((active_jobs--))
            done
            
            # Start deployment in background
            deploy_lab "$config_file" "$CREDENTIALS_FILE" "$lab_id" &
            local pid=$!
            pids+=($pid)
            ((active_jobs++))
            
            print_info "Started deployment for lab $lab_id (PID: $pid)"
        fi
    done

    # Wait for all deployments to complete
    print_status "Waiting for all deployments to complete..."
    local success_count=0
    local failure_count=0

    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
    done

    # Summary
    print_status "Deployment Summary"
    print_status "=================="
    print_success "Successful deployments: $success_count"
    if [[ "$failure_count" -gt 0 ]]; then
        print_error "Failed deployments: $failure_count"
    fi

    print_info "Check individual deployment logs for details:"
    for config_file in "$temp_dir"/lab_configs/lab_*.conf; do
        if [[ -f "$config_file" ]]; then
            local lab_id=$(basename "$config_file" .conf | sed 's/^lab_//')
            if [[ -f "deployment_${lab_id}.log" ]]; then
                print_info "  - deployment_${lab_id}.log"
            fi
        fi
    done

    # Finalize multi-lab log
    finalize_multi_lab_log "$lab_count" "$success_count" "$failure_count"

    if [[ "$failure_count" -gt 0 ]]; then
        exit 1
    else
        print_success "All deployments completed successfully!"
        exit 0
    fi
}

# Run main function with all arguments
main "$@"
