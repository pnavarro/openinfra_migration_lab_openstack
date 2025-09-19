# SSH Jump Host Deployment Guide

## Overview

This guide explains how to use the RHOSO Ansible playbooks when you need to connect to your lab environment via an SSH jump host (bastion), which is the typical scenario for RHDP lab environments.

## Your Connection Flow

```
Your Workstation → SSH Jump Host (Bastion) → Lab Environment
                  ssh lab-user@ssh.ocpvdev01.rhdp.net -p 31295
```

## How the Playbooks Handle This

The playbooks have been designed to work seamlessly with this connection model:

1. **Your workstation** runs Ansible
2. **Ansible connects** to the bastion via SSH using your credentials
3. **All operations execute** on the bastion host
4. **SSH delegation** is used for NFS server and compute node configuration

## Key Components

### 1. Modified Inventory Structure

The inventory (`inventory/hosts.yml`) is configured for jump host connectivity:

```yaml
bastion:
  hosts:
    bastion-jumphost:
      ansible_host: "ssh.ocpvdev01.rhdp.net"  # Your jump host
      ansible_user: "lab-user"
      ansible_port: "31295"                   # Your SSH port
      ansible_ssh_pass: "your-password"       # Your password
```

### 2. Delegation for Internal Resources

Internal lab resources (NFS server, compute nodes) are accessed via SSH delegation from the bastion:

```yaml
nfsserver:
  hosts:
    nfs-server:
      ansible_host: "nfsserver"              # Internal hostname
      delegate_to: bastion-jumphost          # Execute from bastion
```

### 3. Specialized Deployment Script

The `deploy-via-jumphost.sh` script provides:
- Inventory validation
- SSH connectivity testing  
- Dry-run capabilities
- Phase-by-phase deployment options

## Step-by-Step Usage

### 1. Initial Setup

```bash
# Clone or navigate to the playbooks directory
cd ansible-playbooks

# Copy the example inventory
cp inventory/hosts.yml.example inventory/hosts.yml

# Edit with your actual values
vim inventory/hosts.yml
```

### 2. Configure Your Environment

Update `inventory/hosts.yml` with:

```yaml
# Your lab details
lab_guid: "a1b2c"                           # Your actual GUID
bastion_hostname: "ssh.ocpvdev01.rhdp.net"  # Your actual hostname  
bastion_port: "31295"                       # Your actual port
bastion_password: "YourPassword"             # Your actual password

# Red Hat credentials (REQUIRED)
registry_username: "your-service-account"
registry_password: "your-token"
rhc_username: "your-rh-username"
rhc_password: "your-rh-password"

# External IPs for OpenShift worker nodes (update if different from defaults)
rhoso_external_ip_worker_1: "172.21.0.21"  # External IP for worker node 1
rhoso_external_ip_worker_2: "172.21.0.22"  # External IP for worker node 2
rhoso_external_ip_worker_3: "172.21.0.23"  # External IP for worker node 3
```

### 3. Verify Configuration

```bash
./deploy-via-jumphost.sh --check-inventory
```

This will:
- Check for "changeme" placeholders
- Validate inventory structure
- Test SSH connectivity to your bastion

### 4. Deploy RHOSO

```bash
# Complete deployment
./deploy-via-jumphost.sh

# Or step-by-step
./deploy-via-jumphost.sh prerequisites
./deploy-via-jumphost.sh install-operators
./deploy-via-jumphost.sh security
./deploy-via-jumphost.sh nfs-server
./deploy-via-jumphost.sh network-isolation
./deploy-via-jumphost.sh control-plane
./deploy-via-jumphost.sh data-plane
./deploy-via-jumphost.sh validation
```

### 5. Enable Optional Services

```bash
./deploy-via-jumphost.sh optional
```

## Advanced Options

### Dry Run Mode

Test what would happen without making changes:

```bash
./deploy-via-jumphost.sh --dry-run full
./deploy-via-jumphost.sh --dry-run control-plane
```

### Verbose Output

Get detailed Ansible output for troubleshooting:

```bash
./deploy-via-jumphost.sh --verbose prerequisites
```

### Individual Phase Deployment

Deploy specific phases only:

```bash
./deploy-via-jumphost.sh control-plane
./deploy-via-jumphost.sh data-plane
```

## Behind the Scenes

### What Happens During Execution

1. **Ansible connects** to your bastion via SSH
2. **Repository cloning** happens on the bastion
3. **oc commands** execute on the bastion (where `oc` is already configured)
4. **Kubernetes operations** use the bastion's OpenShift connection
5. **SSH delegation** connects to internal lab resources when needed

### Network Flow

```
Workstation → Bastion → OpenShift API
           ↳→ Bastion → NFS Server (via SSH)
           ↳→ Bastion → Compute Node (via SSH)
```

### Security Considerations

- Your bastion password is used for the initial SSH connection
- Lab SSH keys (on bastion) are used for internal resource access
- Red Hat credentials are securely passed to create secrets in OpenShift
- All operations respect the lab's network isolation

## Troubleshooting

### Connection Issues

```bash
# Test SSH connectivity manually
ssh lab-user@ssh.ocpvdev01.rhdp.net -p 31295

# Check inventory configuration
./deploy-via-jumphost.sh --check-inventory
```

### Authentication Problems

- Verify bastion credentials in inventory
- Check Red Hat registry credentials are valid
- Ensure subscription manager credentials are correct

### Deployment Issues

```bash
# Run with verbose output
./deploy-via-jumphost.sh --verbose <phase>

# Use dry-run to check what would happen
./deploy-via-jumphost.sh --dry-run <phase>
```

## Benefits of This Approach

1. **No VPN required** - Works with standard RHDP SSH access
2. **Secure** - Uses lab's existing SSH key infrastructure
3. **Automated** - Converts all manual steps to automation
4. **Resumable** - Can restart from any phase
5. **Verifiable** - Dry-run mode lets you validate before executing

This setup allows you to run the complete RHOSO deployment from your workstation while leveraging the lab's bastion host for all the actual deployment operations.
