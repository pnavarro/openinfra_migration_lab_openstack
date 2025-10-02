#!/bin/bash
# Test script for multi-lab deployment parsing
# This script tests the parsing functionality without actually deploying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/test-multi-lab-$$"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Test parsing function (extracted from main script)
test_parse_lab_config() {
    local config_file="$1"
    local temp_dir="$2"
    
    if [[ ! -f "$config_file" ]]; then
        echo "Lab configuration file not found: $config_file"
        return 1
    fi
    
    print_status "Testing parsing of: $config_file"
    
    # Create directory for parsed lab configs
    mkdir -p "$temp_dir/lab_configs"
    
    # Parse the lab configuration file
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
                print_info "Completed parsing lab: $current_lab"
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
            
            print_info "Found lab: $current_lab"
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
                print_info "  SSH: lab-user@$bastion_host:$bastion_port"
            fi
            continue
        fi
        
        # Parse SSH password
        if [[ "$line" =~ Enter\ ssh\ password\ when\ prompted:\ ([^[:space:]]+) ]]; then
            local bastion_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"bastion_password\"]=\"$bastion_password\"" >> "$lab_config_file"
                print_info "  Password: ***"
            fi
            continue
        fi
        
        # Parse admin password
        if [[ "$line" =~ User\ admin\ with\ password\ ([^[:space:]]+)\ is\ cluster\ admin ]]; then
            local admin_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"ocp_admin_password\"]=\"$admin_password\"" >> "$lab_config_file"
                print_info "  Admin password: ***"
            fi
            continue
        fi
        
        # Parse OpenShift console URL
        if [[ "$line" =~ OpenShift\ Console:\ (https://[^[:space:]]+) ]]; then
            local console_url="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"ocp_console_url\"]=\"$console_url\"" >> "$lab_config_file"
                print_info "  Console: $console_url"
            fi
            continue
        fi
        
        # Parse external IP variables
        if [[ "$line" =~ EXTERNAL_IP_([^=]+)=(.+) ]]; then
            local ip_type="${BASH_REMATCH[1],,}"  # Convert to lowercase
            local ip_value="${BASH_REMATCH[2]}"
            if [[ -n "$lab_config_file" ]]; then
                echo "  [\"rhoso_external_ip_${ip_type}\"]=\"$ip_value\"" >> "$lab_config_file"
                print_info "  External IP $ip_type: $ip_value"
            fi
            continue
        fi
        
        # Parse data section (YAML-like format)
        if [[ "$in_data_section" == "true" && "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]// /_}"  # Replace spaces with underscores
            local value="${BASH_REMATCH[2]}"
            
            # Clean up the value (remove quotes, handle multiline)
            value=$(echo "$value" | sed 's/^["\x27]\|["\x27]$//g' | sed 's/^[[:space:]]*\|[[:space:]]*$//g')
            
            if [[ -n "$lab_config_file" && -n "$value" ]]; then
                echo "  [\"$key\"]=\"$value\"" >> "$lab_config_file"
                print_info "  Data: $key = $value"
            fi
            continue
        fi
        
    done < "$config_file"
    
    # Close the last lab config
    if [[ -n "$current_lab" && -n "$lab_config_file" ]]; then
        echo ")" >> "$lab_config_file"
        ((lab_count++))
        print_info "Completed parsing lab: $current_lab"
    fi
    
    print_status "Successfully parsed $lab_count labs"
    
    # Display parsed configurations
    for config in "$temp_dir/lab_configs"/*.conf; do
        if [[ -f "$config" ]]; then
            echo ""
            print_info "Configuration file: $(basename "$config")"
            echo "----------------------------------------"
            cat "$config"
            echo "----------------------------------------"
        fi
    done
    
    return $lab_count
}

# Main test function
main() {
    local config_file="${1:-../labs_to_be_deployed}"
    
    print_status "Multi-Lab Deployment Parser Test"
    print_status "Config file: $config_file"
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Cleanup function
    cleanup() {
        print_status "Cleaning up test files..."
        rm -rf "$TEMP_DIR"
    }
    trap cleanup EXIT
    
    # Test parsing
    test_parse_lab_config "$config_file" "$TEMP_DIR"
    local lab_count=$?
    
    if [[ $lab_count -gt 0 ]]; then
        print_status "✅ Test passed! Found and parsed $lab_count labs"
        print_status "Parsed configurations are available in: $TEMP_DIR/lab_configs/"
        
        # Keep temp dir for inspection
        trap - EXIT
        print_status "Temporary files preserved for inspection: $TEMP_DIR"
    else
        print_status "❌ Test failed! No labs were parsed"
        exit 1
    fi
}

# Show usage if help requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [CONFIG_FILE]"
    echo ""
    echo "Test the multi-lab deployment parsing functionality."
    echo ""
    echo "Arguments:"
    echo "  CONFIG_FILE    Lab configuration file to test (default: ../labs_to_be_deployed)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Test with default file"
    echo "  $0 ../labs_to_be_deployed    # Test with specific file"
    exit 0
fi

# Run main function
main "$@"
