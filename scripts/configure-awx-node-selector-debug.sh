#!/bin/bash

# Enhanced script to configure AWX instance group with nodeSelector for conversion host connectivity
# Usage: ./configure-awx-node-selector-debug.sh <rhoso_conversion_host_ip>

set -euo pipefail

# Configuration
AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"
INSTANCE_GROUP_NAME="${INSTANCE_GROUP_NAME:-default}"
SSH_PORT="${SSH_PORT:-22}"
TIMEOUT="${TIMEOUT:-5}"
DEBUG="${DEBUG:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${YELLOW}[DEBUG]${NC} $1"
    fi
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 <rhoso_conversion_host_ip>

This script:
1. Tests SSH connectivity from OpenShift nodes to the conversion host
2. Identifies which node can reach the conversion host
3. Updates AWX instance group with nodeSelector for that node

Parameters:
  rhoso_conversion_host_ip    IP address of the RHOSO conversion host

Environment Variables:
  AWX_NAMESPACE              AWX namespace (default: awx)
  INSTANCE_GROUP_NAME        AWX instance group name (default: default)
  SSH_PORT                   SSH port to test (default: 22)
  TIMEOUT                    Connection timeout in seconds (default: 5)
  DEBUG                      Enable debug output (default: false)

Example:
  $0 192.168.2.26
  DEBUG=true $0 192.168.2.26
EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if oc is available
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we're logged into OpenShift
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster. Please run 'oc login' first"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to get OpenShift nodes
get_openshift_nodes() {
    local nodes
    nodes=$(oc get nodes --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null) || {
        print_error "Failed to get OpenShift nodes"
        exit 1
    }
    
    if [[ -z "$nodes" ]]; then
        print_error "No OpenShift nodes found"
        exit 1
    fi
    
    echo "$nodes"
}

# Function to test SSH connectivity from a node
test_ssh_connectivity() {
    local node_name="$1"
    local target_ip="$2"
    
    print_info "Testing SSH connectivity from node: $node_name to $target_ip:$SSH_PORT" >&2
    
    # Create debug pod and test connectivity
    local result
    result=$(oc debug node/"$node_name" --quiet -- bash -c "
        timeout $TIMEOUT nc -vz -w$TIMEOUT $target_ip $SSH_PORT 2>&1 && echo 'SUCCESS' || echo 'FAILED'
    " 2>/dev/null | tail -1)
    
    if [[ "$result" == "SUCCESS" ]]; then
        print_success "Node $node_name can reach $target_ip:$SSH_PORT" >&2
        return 0
    else
        print_warning "Node $node_name cannot reach $target_ip:$SSH_PORT" >&2
        return 1
    fi
}

# Function to find node with connectivity
find_accessible_node() {
    local target_ip="$1"
    local nodes="$2"
    local accessible_node=""
    
    print_info "Testing SSH connectivity from all nodes to $target_ip..." >&2
    
    while IFS= read -r node; do
        [[ -z "$node" ]] && continue
        
        if test_ssh_connectivity "$node" "$target_ip"; then
            accessible_node="$node"
            break
        fi
    done <<< "$nodes"
    
    if [[ -z "$accessible_node" ]]; then
        print_error "No OpenShift node can reach $target_ip:$SSH_PORT" >&2
        exit 1
    fi
    
    echo "$accessible_node"
}

# Function to get AWX admin password
get_awx_admin_password() {
    print_info "Getting AWX admin password..."
    
    local password
    password=$(oc get secret awx-admin-password -n "$AWX_NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d) || {
        print_error "Failed to get AWX admin password from secret awx-admin-password in namespace $AWX_NAMESPACE"
        exit 1
    }
    
    echo "$password"
}

# Function to get AWX service URL
get_awx_url() {
    print_info "Getting AWX service URL..."
    
    local awx_route
    awx_route=$(oc get route awx -n "$AWX_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null) || {
        print_error "Failed to get AWX route in namespace $AWX_NAMESPACE"
        exit 1
    }
    
    echo "https://$awx_route"
}

# Function to get current instance group configuration
get_current_instance_group_config() {
    local awx_url="$1"
    local awx_password="$2"
    
    print_info "Getting current instance group configuration..."
    
    local response
    response=$(curl -s -k -u "admin:$awx_password" \
        "$awx_url/api/v2/instance_groups/" \
        -H "Content-Type: application/json") || {
        print_error "Failed to get instance groups from AWX API"
        exit 1
    }
    
    print_debug "Instance groups response: $response"
    
    local instance_group_config
    instance_group_config=$(echo "$response" | jq -r ".results[] | select(.name == \"$INSTANCE_GROUP_NAME\")")
    
    if [[ -z "$instance_group_config" || "$instance_group_config" == "null" ]]; then
        print_error "Instance group '$INSTANCE_GROUP_NAME' not found in AWX"
        exit 1
    fi
    
    echo "$instance_group_config"
}

# Function to update AWX instance group with enhanced error handling
update_awx_instance_group() {
    local node_name="$1"
    local awx_url="$2"
    local awx_password="$3"
    
    print_info "Updating AWX instance group '$INSTANCE_GROUP_NAME' with nodeSelector for node: $node_name"
    
    # Get current instance group configuration
    local current_config
    current_config=$(get_current_instance_group_config "$awx_url" "$awx_password")
    
    local instance_group_id
    instance_group_id=$(echo "$current_config" | jq -r '.id')
    
    print_info "Found instance group '$INSTANCE_GROUP_NAME' with ID: $instance_group_id"
    print_debug "Current instance group config: $current_config"
    
    # Check current pod_spec_override
    local current_pod_spec
    current_pod_spec=$(echo "$current_config" | jq -r '.pod_spec_override // empty')
    
    if [[ -n "$current_pod_spec" ]]; then
        print_warning "Instance group already has pod_spec_override:"
        echo "$current_pod_spec"
        print_info "This will be replaced with the new nodeSelector configuration"
    fi
    
    # Create the pod spec override as proper YAML
    local pod_spec_yaml
    pod_spec_yaml="spec:
  nodeSelector:
    kubernetes.io/hostname: $node_name"
    
    print_debug "Pod spec YAML to apply:"
    print_debug "$pod_spec_yaml"
    
    # Prepare the patch data with proper JSON escaping
    local patch_data
    patch_data=$(jq -n --arg pod_spec "$pod_spec_yaml" '{pod_spec_override: $pod_spec}')
    
    print_debug "Patch data: $patch_data"
    
    # Update instance group
    local response
    response=$(curl -s -k -u "admin:$awx_password" \
        -X PATCH \
        "$awx_url/api/v2/instance_groups/$instance_group_id/" \
        -H "Content-Type: application/json" \
        -d "$patch_data") || {
        print_error "Failed to update AWX instance group"
        exit 1
    }
    
    print_debug "Update response: $response"
    
    # Check if update was successful
    local updated_name
    updated_name=$(echo "$response" | jq -r '.name' 2>/dev/null)
    
    if [[ "$updated_name" == "$INSTANCE_GROUP_NAME" ]]; then
        print_success "Successfully updated AWX instance group '$INSTANCE_GROUP_NAME' with nodeSelector for node: $node_name"
        
        # Check if pod_spec_override was actually set
        local updated_pod_spec
        updated_pod_spec=$(echo "$response" | jq -r '.pod_spec_override // empty')
        
        if [[ -n "$updated_pod_spec" ]]; then
            print_success "pod_spec_override was successfully applied:"
            echo "$updated_pod_spec"
        else
            print_warning "pod_spec_override appears to be empty in the response"
        fi
    else
        print_error "Failed to update AWX instance group. Response: $response"
        
        # Try to extract error message
        local error_msg
        error_msg=$(echo "$response" | jq -r '.detail // .error // "Unknown error"' 2>/dev/null)
        print_error "Error details: $error_msg"
        exit 1
    fi
}

# Function to verify the configuration with enhanced checks
verify_configuration() {
    local node_name="$1"
    local awx_url="$2"
    local awx_password="$3"
    
    print_info "Verifying AWX instance group configuration..."
    
    # Wait a moment for the configuration to propagate
    sleep 2
    
    local updated_config
    updated_config=$(get_current_instance_group_config "$awx_url" "$awx_password")
    
    local instance_group_config
    instance_group_config=$(echo "$updated_config" | jq -r '.pod_spec_override // empty')
    
    if [[ -z "$instance_group_config" ]]; then
        print_error "Configuration verification failed: pod_spec_override is empty"
        return 1
    fi
    
    if echo "$instance_group_config" | grep -q "kubernetes.io/hostname: $node_name"; then
        print_success "Configuration verified: AWX jobs will run on node $node_name"
        echo
        echo "Instance group pod_spec_override:"
        echo "$instance_group_config"
        return 0
    else
        print_warning "Configuration verification failed: nodeSelector not found or incorrect"
        echo "Current pod_spec_override:"
        echo "$instance_group_config"
        return 1
    fi
}

# Function to check AWX version and capabilities
check_awx_version() {
    local awx_url="$1"
    local awx_password="$2"
    
    print_info "Checking AWX version and capabilities..."
    
    local config_response
    config_response=$(curl -s -k -u "admin:$awx_password" \
        "$awx_url/api/v2/config/" \
        -H "Content-Type: application/json") || {
        print_warning "Could not retrieve AWX configuration"
        return 1
    }
    
    local awx_version
    awx_version=$(echo "$config_response" | jq -r '.version // "unknown"')
    
    print_info "AWX Version: $awx_version"
    
    # Check if instance groups endpoint is accessible
    local ig_response
    ig_response=$(curl -s -k -u "admin:$awx_password" \
        "$awx_url/api/v2/instance_groups/" \
        -H "Content-Type: application/json") || {
        print_error "Cannot access instance groups API endpoint"
        return 1
    }
    
    local ig_count
    ig_count=$(echo "$ig_response" | jq -r '.count // 0')
    
    print_info "Found $ig_count instance groups"
    
    return 0
}

# Main function
main() {
    # Check arguments
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi
    
    local rhoso_conversion_host_ip="$1"
    
    # Validate IP address format
    if ! [[ "$rhoso_conversion_host_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_error "Invalid IP address format: $rhoso_conversion_host_ip"
        exit 1
    fi
    
    print_info "Starting AWX nodeSelector configuration for conversion host: $rhoso_conversion_host_ip"
    if [[ "$DEBUG" == "true" ]]; then
        print_info "Debug mode enabled"
    fi
    echo
    
    # Check prerequisites
    check_prerequisites
    echo
    
    # Get OpenShift nodes
    print_info "Getting OpenShift nodes..."
    local nodes
    nodes=$(get_openshift_nodes)
    print_success "Found $(echo "$nodes" | wc -l) OpenShift nodes"
    echo
    
    # Find node with connectivity
    local accessible_node
    accessible_node=$(find_accessible_node "$rhoso_conversion_host_ip" "$nodes")
    print_success "Found accessible node: $accessible_node"
    echo
    
    # Get AWX credentials and URL
    local awx_password awx_url
    awx_password=$(get_awx_admin_password)
    awx_url=$(get_awx_url)
    print_success "AWX URL: $awx_url"
    echo
    
    # Check AWX version and capabilities
    check_awx_version "$awx_url" "$awx_password"
    echo
    
    # Update AWX instance group
    update_awx_instance_group "$accessible_node" "$awx_url" "$awx_password"
    echo
    
    # Verify configuration
    if verify_configuration "$accessible_node" "$awx_url" "$awx_password"; then
        echo
        print_success "AWX configuration completed successfully!"
        print_info "All AWX jobs in the '$INSTANCE_GROUP_NAME' instance group will now run on node: $accessible_node"
    else
        echo
        print_error "Configuration verification failed. Please check the AWX web interface manually."
        print_info "You can access AWX at: $awx_url"
        print_info "Navigate to Instance Groups -> $INSTANCE_GROUP_NAME to verify the configuration"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
