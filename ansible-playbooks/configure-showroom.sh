#!/bin/bash

# Configure Showroom Git Repository URL
# This script runs the configure-showroom.yml playbook via SSH jump host

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK_DIR="$SCRIPT_DIR"

# Default values
INVENTORY_FILE=""
GIT_REPO_URL="https://github.com/pnavarro/openinfra_migration_lab_openstack"
SHOWROOM_NAMESPACE="showroom"
SHOWROOM_DEPLOYMENT="showroom"
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
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

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure Showroom Git Repository URL via SSH jump host

OPTIONS:
    -i, --inventory FILE     Ansible inventory file (required)
    -r, --repo-url URL      Git repository URL (default: https://github.com/pnavarro/openinfra_migration_lab_openstack)
    -n, --namespace NAME    Showroom namespace (default: showroom)
    -d, --deployment NAME   Showroom deployment name (default: showroom)
    --dry-run              Run in check mode (no changes)
    -v, --verbose          Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    # Configure showroom for cluster-7m9ft
    $0 -i inventory/hosts-cluster-7m9ft.yml

    # Configure with custom repository URL
    $0 -i inventory/hosts-cluster-7h86j.yml -r https://github.com/myuser/my-repo

    # Dry run to see what would be changed
    $0 -i inventory/hosts-cluster-6hwf7.yml --dry-run

    # Verbose output
    $0 -i inventory/hosts.yml -v

INVENTORY FILES:
    Available inventory files in inventory/ directory:
$(find "$PLAYBOOK_DIR/inventory" -name "hosts*.yml" 2>/dev/null | sed 's|.*/|    - |' || echo "    No inventory files found")

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -r|--repo-url)
            GIT_REPO_URL="$2"
            shift 2
            ;;
        -n|--namespace)
            SHOWROOM_NAMESPACE="$2"
            shift 2
            ;;
        -d|--deployment)
            SHOWROOM_DEPLOYMENT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
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

# Validate required parameters
if [[ -z "$INVENTORY_FILE" ]]; then
    print_error "Inventory file is required. Use -i or --inventory option."
    usage
    exit 1
fi

# Check if inventory file exists
if [[ ! -f "$INVENTORY_FILE" ]]; then
    print_error "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

# Check if playbook exists
PLAYBOOK_FILE="$PLAYBOOK_DIR/configure-showroom.yml"
if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    print_error "Playbook not found: $PLAYBOOK_FILE"
    exit 1
fi

# Build ansible-playbook command
ANSIBLE_CMD=(
    "ansible-playbook"
    "-i" "$INVENTORY_FILE"
    "$PLAYBOOK_FILE"
    "-e" "showroom_git_repo_url=$GIT_REPO_URL"
    "-e" "showroom_namespace=$SHOWROOM_NAMESPACE"
    "-e" "showroom_deployment=$SHOWROOM_DEPLOYMENT"
)

# Add optional flags
if [[ "$DRY_RUN" == "true" ]]; then
    ANSIBLE_CMD+=("--check")
    print_warning "Running in DRY RUN mode - no changes will be made"
fi

if [[ "$VERBOSE" == "true" ]]; then
    ANSIBLE_CMD+=("-v")
fi

# Display configuration
print_status "Configuration:"
echo "  Inventory File: $INVENTORY_FILE"
echo "  Git Repository URL: $GIT_REPO_URL"
echo "  Showroom Namespace: $SHOWROOM_NAMESPACE"
echo "  Showroom Deployment: $SHOWROOM_DEPLOYMENT"
echo "  Dry Run: $DRY_RUN"
echo "  Verbose: $VERBOSE"
echo ""

# Execute the playbook
print_status "Executing ansible-playbook command:"
echo "  ${ANSIBLE_CMD[*]}"
echo ""

if "${ANSIBLE_CMD[@]}"; then
    print_success "Showroom configuration completed successfully!"
else
    print_error "Showroom configuration failed!"
    exit 1
fi
