#!/bin/bash
# Example usage script for multi-lab deployment
# This script demonstrates how to use the multi-lab deployment system

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_example() {
    echo -e "${YELLOW}[EXAMPLE]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

show_header() {
    echo ""
    echo "=============================================="
    echo "$1"
    echo "=============================================="
    echo ""
}

create_sample_lab_config() {
    local config_file="$1"
    
    cat > "$config_file" << 'EOF'
Service	Assigned Email	Details
openshift-cnv.osp-on-ocp-cnv.dev-abc123	
- unassigned -

Lab UI
https://showroom-showroom.apps.cluster-abc123.dynamic.redhatworkshops.io/ 
Messages
OpenShift Console: https://console-openshift-console.apps.cluster-abc123.dynamic.redhatworkshops.io
OpenShift API for command line 'oc' client: https://api.cluster-abc123.dynamic.redhatworkshops.io:6443
Download oc client from http://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.16/openshift-client-linux.tar.gz

RHOSO External IP Allocation Details:
=======================================

Allocation Name: cluster-abc123
Cluster: ocpvdev01
Network Subnet: 192.168.0.0/24
Network CIDR: 192.168.0.0/24

Allocated IP Addresses:
EXTERNAL_IP_WORKER_1=192.168.5.10
EXTERNAL_IP_WORKER_2=192.168.5.11
EXTERNAL_IP_WORKER_3=192.168.5.12
EXTERNAL_IP_BASTION=192.168.5.13
PUBLIC_NET_START=192.168.5.20
PUBLIC_NET_END=192.168.5.30
CONVERSION_HOST_IP=192.168.5.25

Environment Variables (copy and paste):
export EXTERNAL_IP_WORKER_1=192.168.5.10
export EXTERNAL_IP_WORKER_2=192.168.5.11
export EXTERNAL_IP_WORKER_3=192.168.5.12
export EXTERNAL_IP_BASTION=192.168.5.13
export PUBLIC_NET_START=192.168.5.20
export PUBLIC_NET_END=192.168.5.30
export CONVERSION_HOST_IP=192.168.5.25

Authentication via htpasswd is enabled on this cluster.

User admin with password ExamplePass123 is cluster admin.
OpenShift GitOps ArgoCD: https://openshift-gitops-server-openshift-gitops.apps.cluster-abc123.dynamic.redhatworkshops.io
Lab instructions: https://showroom-showroom.apps.cluster-abc123.dynamic.redhatworkshops.io/
You can access your bastion via SSH:
ssh lab-user@ssh.ocpvdev01.rhdp.net -p 30123

Enter ssh password when prompted: ExampleSSHPass

Data
openshift-cnv.osp-on-ocp-cnv.dev:
  bastion_public_hostname: ssh.ocpvdev01.rhdp.net
  bastion_ssh_command: ssh lab-user@ssh.ocpvdev01.rhdp.net -p 30123
  bastion_ssh_password: ExampleSSHPass
  bastion_ssh_port: '30123'
  bastion_ssh_user_name: lab-user
  cloud_provider: openshift_cnv
  guid: abc123
  openshift_api_server_url: https://api.cluster-abc123.dynamic.redhatworkshops.io:6443
  openshift_api_url: https://api.cluster-abc123.dynamic.redhatworkshops.io:6443
  openshift_cluster_admin_password: ExamplePass123
  openshift_cluster_admin_username: admin
  openshift_cluster_console_url: https://console-openshift-console.apps.cluster-abc123.dynamic.redhatworkshops.io
  rhoso_external_ip_worker_1: 192.168.5.10
  rhoso_external_ip_worker_2: 192.168.5.11
  rhoso_external_ip_worker_3: 192.168.5.12
  rhoso_external_ip_bastion: 192.168.5.13
  rhoso_public_net_start: 192.168.5.20
  rhoso_public_net_end: 192.168.5.30
  rhoso_conversion_host_ip: 192.168.5.25
openshift-cnv.osp-on-ocp-cnv.dev-def456	
- unassigned -

Lab UI
https://showroom-showroom.apps.cluster-def456.dynamic.redhatworkshops.io/ 
Messages
OpenShift Console: https://console-openshift-console.apps.cluster-def456.dynamic.redhatworkshops.io
OpenShift API for command line 'oc' client: https://api.cluster-def456.dynamic.redhatworkshops.io:6443
Download oc client from http://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.16/openshift-client-linux.tar.gz

RHOSO External IP Allocation Details:
=======================================

Allocation Name: cluster-def456
Cluster: ocpvdev01
Network Subnet: 192.168.0.0/24
Network CIDR: 192.168.0.0/24

Allocated IP Addresses:
EXTERNAL_IP_WORKER_1=192.168.6.10
EXTERNAL_IP_WORKER_2=192.168.6.11
EXTERNAL_IP_WORKER_3=192.168.6.12
EXTERNAL_IP_BASTION=192.168.6.13
PUBLIC_NET_START=192.168.6.20
PUBLIC_NET_END=192.168.6.30
CONVERSION_HOST_IP=192.168.6.25

Environment Variables (copy and paste):
export EXTERNAL_IP_WORKER_1=192.168.6.10
export EXTERNAL_IP_WORKER_2=192.168.6.11
export EXTERNAL_IP_WORKER_3=192.168.6.12
export EXTERNAL_IP_BASTION=192.168.6.13
export PUBLIC_NET_START=192.168.6.20
export PUBLIC_NET_END=192.168.6.30
export CONVERSION_HOST_IP=192.168.6.25

Authentication via htpasswd is enabled on this cluster.

User admin with password ExamplePass456 is cluster admin.
OpenShift GitOps ArgoCD: https://openshift-gitops-server-openshift-gitops.apps.cluster-def456.dynamic.redhatworkshops.io
Lab instructions: https://showroom-showroom.apps.cluster-def456.dynamic.redhatworkshops.io/
You can access your bastion via SSH:
ssh lab-user@ssh.ocpvdev01.rhdp.net -p 30456

Enter ssh password when prompted: ExampleSSHPass2

Data
openshift-cnv.osp-on-ocp-cnv.dev:
  bastion_public_hostname: ssh.ocpvdev01.rhdp.net
  bastion_ssh_command: ssh lab-user@ssh.ocpvdev01.rhdp.net -p 30456
  bastion_ssh_password: ExampleSSHPass2
  bastion_ssh_port: '30456'
  bastion_ssh_user_name: lab-user
  cloud_provider: openshift_cnv
  guid: def456
  openshift_api_server_url: https://api.cluster-def456.dynamic.redhatworkshops.io:6443
  openshift_api_url: https://api.cluster-def456.dynamic.redhatworkshops.io:6443
  openshift_cluster_admin_password: ExamplePass456
  openshift_cluster_admin_username: admin
  openshift_cluster_console_url: https://console-openshift-console.apps.cluster-def456.dynamic.redhatworkshops.io
  rhoso_external_ip_worker_1: 192.168.6.10
  rhoso_external_ip_worker_2: 192.168.6.11
  rhoso_external_ip_worker_3: 192.168.6.12
  rhoso_external_ip_bastion: 192.168.6.13
  rhoso_public_net_start: 192.168.6.20
  rhoso_public_net_end: 192.168.6.30
  rhoso_conversion_host_ip: 192.168.6.25
EOF
}

create_sample_credentials() {
    local creds_file="$1"
    
    cat > "$creds_file" << 'EOF'
# Sample credentials file - REPLACE WITH YOUR ACTUAL CREDENTIALS
# Red Hat Registry Service Account Credentials
# Get these from: https://access.redhat.com/articles/RegistryAuthentication#creating-registry-service-accounts-6
registry_username: "YOUR_SERVICE_ACCOUNT_ID|your-service-account-name"
registry_password: "YOUR_REGISTRY_TOKEN_HERE"

# Red Hat Customer Portal Credentials
# Your login credentials for https://access.redhat.com
rhc_username: "your-rh-username@email.com"
rhc_password: "YourRHPassword123"
EOF
}

main() {
    show_header "Multi-Lab RHOSO Deployment - Example Usage"
    
    print_info "This script demonstrates how to use the multi-lab deployment system."
    print_info "It will create sample files and show example commands."
    echo ""
    
    # Step 1: Create sample lab configuration
    show_header "Step 1: Create Sample Lab Configuration"
    
    local sample_config="$SCRIPT_DIR/sample_labs_config"
    print_step "Creating sample lab configuration file: $sample_config"
    
    create_sample_lab_config "$sample_config"
    print_success "Sample lab configuration created!"
    
    print_info "This file contains configuration for 2 example labs:"
    print_info "- cluster-abc123 (SSH port 30123)"
    print_info "- cluster-def456 (SSH port 30456)"
    echo ""
    
    # Step 2: Create sample credentials
    show_header "Step 2: Create Sample Credentials File"
    
    local sample_creds="$SCRIPT_DIR/sample_credentials.yml"
    print_step "Creating sample credentials file: $sample_creds"
    
    create_sample_credentials "$sample_creds"
    print_success "Sample credentials file created!"
    
    print_info "⚠️  IMPORTANT: Edit this file with your actual Red Hat credentials before deployment!"
    echo ""
    
    # Step 3: Show basic usage examples
    show_header "Step 3: Basic Usage Examples"
    
    print_step "List available labs in configuration:"
    print_example "./scripts/deploy_multiple_labs.sh --list $sample_config"
    echo ""
    
    print_step "Parse configuration and generate inventory files:"
    print_example "python3 ./scripts/parse_lab_config.py $sample_config"
    echo ""
    
    print_step "Test environment setup:"
    print_example "./scripts/test_deployment_setup.sh"
    echo ""
    
    print_step "Perform a dry run (no actual changes):"
    print_example "./scripts/deploy_multiple_labs.sh -d $sample_config"
    echo ""
    
    print_step "Deploy all labs with default settings:"
    print_example "./scripts/deploy_multiple_labs.sh --credentials $sample_creds $sample_config"
    echo ""
    
    # Step 4: Advanced usage examples
    show_header "Step 4: Advanced Usage Examples"
    
    print_step "Deploy with limited parallelism (safer for resource-constrained environments):"
    print_example "./scripts/deploy_multiple_labs.sh -j 1 --credentials $sample_creds $sample_config"
    echo ""
    
    print_step "Deploy only prerequisites phase across all labs:"
    print_example "./scripts/deploy_multiple_labs.sh -p prerequisites --credentials $sample_creds $sample_config"
    echo ""
    
    print_step "Deploy with verbose output and dry run:"
    print_example "./scripts/deploy_multiple_labs.sh -d -v --credentials $sample_creds $sample_config"
    echo ""
    
    print_step "Force regeneration of inventory files:"
    print_example "./scripts/deploy_multiple_labs.sh -f --credentials $sample_creds $sample_config"
    echo ""
    
    # Step 5: Monitoring and troubleshooting
    show_header "Step 5: Monitoring and Troubleshooting"
    
    print_step "Monitor deployment progress (run during deployment):"
    print_example "tail -f deployment_logs/*.log"
    echo ""
    
    print_step "Check for deployment errors:"
    print_example "grep -i error deployment_logs/*.log"
    echo ""
    
    print_step "View specific lab deployment log:"
    print_example "cat deployment_logs/deploy_abc123_*.log"
    echo ""
    
    print_step "Test connectivity to a specific lab (after inventory generation):"
    print_example "cd ansible-playbooks && ansible -i generated_inventories/hosts-cluster-abc123.yml -m ping all"
    echo ""
    
    # Step 6: Manual single-lab deployment
    show_header "Step 6: Manual Single-Lab Deployment"
    
    print_step "Deploy a single lab manually:"
    print_example "cd ansible-playbooks"
    print_example "ansible-playbook -i generated_inventories/hosts-cluster-abc123.yml site.yml"
    echo ""
    
    print_step "Deploy specific phase for single lab:"
    print_example "cd ansible-playbooks"
    print_example "ansible-playbook -i generated_inventories/hosts-cluster-abc123.yml site.yml --tags control-plane"
    echo ""
    
    # Step 7: File structure after deployment
    show_header "Step 7: Generated File Structure"
    
    print_info "After running the parser and deployment, you'll have:"
    echo ""
    print_info "ansible-playbooks/"
    print_info "├── generated_inventories/"
    print_info "│   ├── hosts-cluster-abc123.yml    # Lab-specific inventory"
    print_info "│   ├── hosts-cluster-def456.yml    # Lab-specific inventory"
    print_info "│   └── lab_summary.json            # Summary of all labs"
    print_info "└── [existing ansible files]"
    echo ""
    print_info "deployment_logs/"
    print_info "├── deploy_abc123_20231201_143022.log"
    print_info "└── deploy_def456_20231201_143025.log"
    echo ""
    
    # Step 8: Cleanup instructions
    show_header "Step 8: Cleanup (Optional)"
    
    print_step "Remove generated files:"
    print_example "rm -rf ansible-playbooks/generated_inventories/"
    print_example "rm -rf deployment_logs/"
    print_example "rm -f scripts/sample_*"
    echo ""
    
    # Step 9: Next steps
    show_header "Step 9: Next Steps"
    
    print_info "To use this system with your actual lab configurations:"
    echo ""
    print_step "1. Replace the sample configuration with your actual lab data"
    print_step "2. Update the credentials file with your Red Hat credentials"
    print_step "3. Run the test script to verify your setup:"
    print_example "./scripts/test_deployment_setup.sh"
    print_step "4. Start with a dry run to validate everything:"
    print_example "./scripts/deploy_multiple_labs.sh -d your_actual_config_file"
    print_step "5. Deploy for real:"
    print_example "./scripts/deploy_multiple_labs.sh --credentials your_credentials.yml your_actual_config_file"
    echo ""
    
    show_header "Example Complete!"
    
    print_success "Sample files created successfully!"
    print_info "Sample configuration: $sample_config"
    print_info "Sample credentials: $sample_creds"
    echo ""
    print_info "📖 For detailed documentation, see: scripts/README.md"
    print_info "🧪 To test your setup, run: ./scripts/test_deployment_setup.sh"
    echo ""
    print_info "Happy deploying! 🚀"
}

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Multi-Lab Deployment - Example Usage"
    echo ""
    echo "Usage: $0"
    echo ""
    echo "This script creates sample configuration files and demonstrates"
    echo "how to use the multi-lab deployment system."
    echo ""
    echo "It will create:"
    echo "  • Sample lab configuration file"
    echo "  • Sample credentials file (template)"
    echo "  • Show example commands for various use cases"
    echo ""
    echo "The sample files are safe to use for testing the parsing"
    echo "functionality, but contain example data that won't work"
    echo "for actual deployments."
    exit 0
fi

# Run main function
main "$@"
