#!/bin/bash
# Test SSH connectivity to lab resources from bastion
# This script helps verify that the SSH connections work before running the full deployment

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
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Get GUID from inventory
GUID=$(grep "lab_guid:" inventory/hosts.yml | cut -d'"' -f2)
BASTION_USER=$(grep "bastion_user:" inventory/hosts.yml | cut -d'"' -f2)

if [[ "$GUID" == "changeme" ]]; then
    print_error "Please update the lab_guid in inventory/hosts.yml"
    exit 1
fi

print_header "Testing SSH connectivity to lab resources"
print_status "Using GUID: $GUID"
print_status "Using SSH key: /home/${BASTION_USER}/.ssh/${GUID}key.pem"

# Test NFS server connectivity
print_header "Testing NFS server connectivity"
ssh -i /home/${BASTION_USER}/.ssh/${GUID}key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@nfsserver 'echo "NFS server connection successful"' && {
    print_status "✅ NFS server (nfsserver) - Connection successful"
} || {
    print_error "❌ NFS server (nfsserver) - Connection failed"
    exit 1
}

# Test compute node connectivity
print_header "Testing compute node connectivity"
ssh -i /home/${BASTION_USER}/.ssh/${GUID}key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@compute01 'echo "Compute node connection successful"' && {
    print_status "✅ Compute node (compute01) - Connection successful"
} || {
    print_error "❌ Compute node (compute01) - Connection failed"
    exit 1
}

# Test sudo access on NFS server
print_header "Testing sudo access on NFS server"
ssh -i /home/${BASTION_USER}/.ssh/${GUID}key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@nfsserver 'sudo whoami' && {
    print_status "✅ NFS server sudo access - Working"
} || {
    print_error "❌ NFS server sudo access - Failed"
    exit 1
}

# Test sudo access on compute node
print_header "Testing sudo access on compute node"
ssh -i /home/${BASTION_USER}/.ssh/${GUID}key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@compute01 'sudo whoami' && {
    print_status "✅ Compute node sudo access - Working"
} || {
    print_error "❌ Compute node sudo access - Failed"
    exit 1
}

print_header "All SSH connectivity tests passed! ✅"
print_status "The ansible playbooks should now work correctly with:"
echo "  - NFS server configuration (nfs-server role)"
echo "  - Compute node configuration (data-plane role)"
print_status "You can now run: ./deploy-via-jumphost.sh"
