# Multi-Lab RHOSO Deployment Scripts

This directory contains scripts for deploying Red Hat OpenStack Services on OpenShift (RHOSO) across multiple lab environments simultaneously.

## Overview

The multi-lab deployment system consists of:

1. **Parser Script** (`parse_lab_config.py`) - Parses lab configuration files and generates Ansible inventories
2. **Deployment Script** (`deploy_multiple_labs.sh`) - Orchestrates parallel deployment across multiple labs
3. **Credentials Template** (`credentials.yml.example`) - Template for storing registry and Red Hat credentials

## Quick Start

### 1. Prepare Lab Configuration File

Create a file containing your lab configurations (like the example provided by your user):

```bash
cat << EOF > labs_to_be_deployed
Service	Assigned Email	Details
openshift-cnv.osp-on-ocp-cnv.dev-hjckm	
- unassigned -

Lab UI
https://showroom-showroom.apps.cluster-7h86j.dynamic.redhatworkshops.io/ 
Messages
OpenShift Console: https://console-openshift-console.apps.cluster-7h86j.dynamic.redhatworkshops.io
OpenShift API for command line 'oc' client: https://api.cluster-7h86j.dynamic.redhatworkshops.io:6443
[... rest of your lab configuration ...]
EOF
```

### 2. Set Up Credentials

```bash
# Copy the credentials template
cp scripts/credentials.yml.example scripts/credentials.yml

# Edit with your actual credentials
vi scripts/credentials.yml
```

### 3. Deploy All Labs

```bash
# Deploy all labs with default settings
./scripts/deploy_multiple_labs.sh labs_to_be_deployed

# Deploy with custom credentials file
./scripts/deploy_multiple_labs.sh --credentials scripts/credentials.yml labs_to_be_deployed

# Deploy with limited parallelism
./scripts/deploy_multiple_labs.sh -j 2 labs_to_be_deployed

# Dry run to test configuration
./scripts/deploy_multiple_labs.sh -d labs_to_be_deployed
```

## Detailed Usage

### Parser Script (`parse_lab_config.py`)

Parses lab configuration files and generates Ansible inventory files.

```bash
# Parse configuration and generate inventories
python3 scripts/parse_lab_config.py labs_to_be_deployed

# This creates:
# - ansible-playbooks/generated_inventories/hosts-cluster-<guid>.yml (for each lab)
# - ansible-playbooks/generated_inventories/lab_summary.json
```

**Input Format**: The parser expects lab configuration data with sections for each environment containing:
- Service names (openshift-cnv.osp-on-ocp-cnv.dev-<guid>)
- OpenShift console and API URLs
- SSH connection details (bastion hostname, port, password)
- IP allocation details (worker IPs, bastion IP, network ranges)
- Authentication credentials

**Output**: 
- Individual Ansible inventory files for each lab
- JSON summary with all extracted lab data

### Deployment Script (`deploy_multiple_labs.sh`)

Orchestrates deployment across multiple labs with parallel execution.

#### Basic Usage

```bash
./scripts/deploy_multiple_labs.sh [OPTIONS] <lab_config_file>
```

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-j, --jobs NUM` | Maximum parallel deployments | 3 |
| `-p, --phase PHASE` | Deployment phase to run | full |
| `-d, --dry-run` | Run in check mode (no changes) | false |
| `-v, --verbose` | Enable verbose output | false |
| `-f, --force` | Force regeneration of inventory files | false |
| `--credentials FILE` | Credentials file path | none |
| `--list` | List labs in config file | false |

#### Deployment Phases

| Phase | Description |
|-------|-------------|
| `prerequisites` | Install required operators (NMState, MetalLB) |
| `install-operators` | Install OpenStack operators |
| `security` | Configure secrets and security |
| `nfs-server` | Configure NFS server |
| `network-isolation` | Set up network isolation |
| `control-plane` | Deploy OpenStack control plane |
| `data-plane` | Configure compute nodes |
| `validation` | Verify deployment |
| `full` | Run complete deployment (default) |
| `optional` | Enable optional services (Heat, Swift) |

#### Examples

```bash
# Deploy all phases for all labs
./scripts/deploy_multiple_labs.sh labs_to_be_deployed

# Deploy only prerequisites with 2 parallel jobs
./scripts/deploy_multiple_labs.sh -j 2 -p prerequisites labs_to_be_deployed

# Dry run with verbose output
./scripts/deploy_multiple_labs.sh -d -v labs_to_be_deployed

# Deploy with custom credentials
./scripts/deploy_multiple_labs.sh --credentials my_credentials.yml labs_to_be_deployed

# List available labs without deploying
./scripts/deploy_multiple_labs.sh --list labs_to_be_deployed

# Force regeneration of inventory files
./scripts/deploy_multiple_labs.sh -f labs_to_be_deployed
```

### Credentials File

Create a YAML file with your Red Hat credentials:

```yaml
# Red Hat Registry Service Account Credentials
# Get these from: https://access.redhat.com/articles/RegistryAuthentication#creating-registry-service-accounts-6
registry_username: "12345678|myserviceaccount"
registry_password: "eyJhbGciOiJSUzUxMiJ9..."

# Red Hat Customer Portal Credentials
rhc_username: "your-rh-username@email.com"
rhc_password: "YourRHPassword123"
```

## File Structure

After running the scripts, you'll have:

```
scripts/
├── deploy_multiple_labs.sh          # Main deployment orchestrator
├── parse_lab_config.py              # Lab configuration parser
├── credentials.yml.example          # Credentials template
└── README.md                        # This file

ansible-playbooks/
├── generated_inventories/           # Generated inventory files
│   ├── hosts-cluster-7h86j.yml     # Lab-specific inventory
│   ├── hosts-cluster-7m9ft.yml     # Lab-specific inventory
│   └── lab_summary.json            # Summary of all labs
└── [existing ansible files]

deployment_logs/                     # Deployment logs
├── deploy_7h86j_20231201_143022.log
└── deploy_7m9ft_20231201_143025.log
```

## Monitoring and Troubleshooting

### Monitoring Deployments

The script provides real-time progress updates:

```
[DEPLOY] Starting deployment of all labs (phase: full, max parallel jobs: 3)
[INFO] Found 2 labs to deploy
[INFO] Started deployment for lab 7h86j (PID: 12345)
[INFO] Started deployment for lab 7m9ft (PID: 12346)
[LAB] [7h86j] Starting full deployment...
[LAB] [7m9ft] Starting full deployment...
[PROGRESS] Progress: 1/2 completed
[LAB] [7h86j] ✅ Deployment completed successfully in 1847s
[PROGRESS] Progress: 2/2 completed
[LAB] [7m9ft] ✅ Deployment completed successfully in 1923s
```

### Log Files

Each lab deployment creates a detailed log file in `deployment_logs/`:

```bash
# View deployment log for a specific lab
tail -f deployment_logs/deploy_7h86j_20231201_143022.log

# Check for errors across all logs
grep -i error deployment_logs/*.log

# Monitor all active deployments
tail -f deployment_logs/*.log
```

### Common Issues

#### 1. Missing Credentials

```
[WARNING] No credentials file provided. You'll need to manually update registry and RH credentials in inventory files.
```

**Solution**: Create and use a credentials file:
```bash
cp scripts/credentials.yml.example scripts/credentials.yml
# Edit credentials.yml with your actual values
./scripts/deploy_multiple_labs.sh --credentials scripts/credentials.yml labs_to_be_deployed
```

#### 2. Inventory Validation Errors

```
[WARNING] Missing required fields in hosts-cluster-xyz.yml: lab_guid bastion_hostname
```

**Solution**: Check your lab configuration file format and regenerate:
```bash
./scripts/deploy_multiple_labs.sh -f labs_to_be_deployed
```

#### 3. SSH Connection Issues

Check the generated inventory files have correct bastion details:
```bash
grep -A 10 "bastion_hostname\|bastion_port\|bastion_password" ansible-playbooks/generated_inventories/hosts-cluster-*.yml
```

#### 4. Deployment Failures

Check individual lab logs:
```bash
# Find failed deployments
grep "❌" deployment_logs/*.log

# Check specific error details
tail -50 deployment_logs/deploy_<failed_lab_guid>_*.log
```

### Manual Operations

#### Deploy a Single Lab

```bash
cd ansible-playbooks
ansible-playbook -i generated_inventories/hosts-cluster-7h86j.yml site.yml
```

#### Deploy Specific Phase for Single Lab

```bash
cd ansible-playbooks
ansible-playbook -i generated_inventories/hosts-cluster-7h86j.yml site.yml --tags control-plane
```

#### Test Connectivity

```bash
cd ansible-playbooks
ansible-playbook -i generated_inventories/hosts-cluster-7h86j.yml -m ping all
```

## Advanced Configuration

### Custom Parallelism

Adjust parallel deployments based on your system resources:

```bash
# Conservative (slower but safer)
./scripts/deploy_multiple_labs.sh -j 1 labs_to_be_deployed

# Aggressive (faster but more resource intensive)
./scripts/deploy_multiple_labs.sh -j 5 labs_to_be_deployed
```

### Selective Deployment

Deploy only specific phases across all labs:

```bash
# Install prerequisites on all labs first
./scripts/deploy_multiple_labs.sh -p prerequisites labs_to_be_deployed

# Then install operators
./scripts/deploy_multiple_labs.sh -p install-operators labs_to_be_deployed

# Continue with other phases...
```

### Custom Inventory Modifications

You can manually edit generated inventory files before deployment:

```bash
# Generate inventories
./scripts/deploy_multiple_labs.sh -f labs_to_be_deployed

# Edit specific lab inventory
vi ansible-playbooks/generated_inventories/hosts-cluster-7h86j.yml

# Deploy without regenerating inventories
./scripts/deploy_multiple_labs.sh labs_to_be_deployed
```

## Prerequisites

- Python 3.6+ with PyYAML module
- Ansible 2.12+
- Bash 4.0+
- SSH access to bastion hosts
- Red Hat Registry Service Account
- Red Hat Customer Portal credentials

## Installation

The scripts are self-contained. Simply clone the repository and ensure prerequisites are met:

```bash
# Install Python dependencies
pip3 install PyYAML

# Install Ansible (if not already installed)
pip3 install ansible

# Verify installation
python3 --version
ansible --version
```

## Security Considerations

- Credentials are stored in plain text files - ensure proper file permissions
- SSH passwords are included in inventory files - protect these files appropriately
- Consider using SSH keys instead of passwords for production deployments
- Log files may contain sensitive information - manage accordingly

```bash
# Set restrictive permissions on credentials file
chmod 600 scripts/credentials.yml

# Set restrictive permissions on generated inventories
chmod 600 ansible-playbooks/generated_inventories/hosts-cluster-*.yml
```

## Contributing

To extend or modify the scripts:

1. **Parser Modifications**: Edit `parse_lab_config.py` to support new configuration formats
2. **Deployment Logic**: Modify `deploy_multiple_labs.sh` for custom deployment workflows
3. **Inventory Templates**: Update the inventory generation in the parser for custom configurations

## Support

For issues and questions:

1. Check the deployment logs in `deployment_logs/`
2. Verify inventory files in `ansible-playbooks/generated_inventories/`
3. Test individual lab deployments manually
4. Review the existing single-lab deployment documentation

## License

This project follows the same license as the parent RHOSO deployment project.