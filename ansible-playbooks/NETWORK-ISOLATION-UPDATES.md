# Network Isolation Updates - Ansible Playbooks

## Overview

The Ansible playbooks have been updated to reflect the changes made to the `network-isolation.adoc` documentation. These changes add support for configurable external IP addresses for OpenShift worker nodes.

## Changes Made

### 1. New Documentation Requirements

The updated `network-isolation.adoc` now includes a step to replace external IP placeholders in the NNCP (NodeNetworkConfigurationPolicy) files:

```bash
# New step in documentation
sed -i 's/EXTERNAL_IP_WORKER_1/{rhoso_external_ip_worker_1}/' osp-ng-nncp-w1.yaml
sed -i 's/EXTERNAL_IP_WORKER_2/{rhoso_external_ip_worker_2}/' osp-ng-nncp-w2.yaml
sed -i 's/EXTERNAL_IP_WORKER_3/{rhoso_external_ip_worker_3}/' osp-ng-nncp-w3.yaml
```

### 2. NNCP File Placeholders

The NNCP files contain the following placeholders that need to be replaced:

- `UUID` → Replaced with lab GUID (existing)
- `EXTERNAL_IP_WORKER_1` → External IP for worker node 1 (new)
- `EXTERNAL_IP_WORKER_2` → External IP for worker node 2 (new)  
- `EXTERNAL_IP_WORKER_3` → External IP for worker node 3 (new)

### 3. Ansible Playbook Updates

#### A. Variables Configuration (`vars/main.yml`)

Added new worker external IP configuration:

```yaml
# OpenShift Worker Node External IP Configuration
worker_external_ips:
  rhoso_external_ip_worker_1: "{{ rhoso_external_ip_worker_1 | default('172.21.0.21') }}"
  rhoso_external_ip_worker_2: "{{ rhoso_external_ip_worker_2 | default('172.21.0.22') }}"
  rhoso_external_ip_worker_3: "{{ rhoso_external_ip_worker_3 | default('172.21.0.23') }}"
```

#### B. Install Operators Role (`roles/install-operators/tasks/main.yml`)

Added new task to replace external IP placeholders:

```yaml
- name: Replace external IP placeholders for worker nodes
  ansible.builtin.replace:
    path: "{{ ansible_env.HOME }}/{{ files_directory }}/{{ item.file }}"
    regexp: "{{ item.placeholder }}"
    replace: "{{ item.value }}"
  loop:
    - file: "osp-ng-nncp-w1.yaml"
      placeholder: "EXTERNAL_IP_WORKER_1"
      value: "{{ worker_external_ips.rhoso_external_ip_worker_1 }}"
    - file: "osp-ng-nncp-w2.yaml"
      placeholder: "EXTERNAL_IP_WORKER_2"
      value: "{{ worker_external_ips.rhoso_external_ip_worker_2 }}"
    - file: "osp-ng-nncp-w3.yaml"
      placeholder: "EXTERNAL_IP_WORKER_3"
      value: "{{ worker_external_ips.rhoso_external_ip_worker_3 }}"
```

#### C. Inventory Updates

Both `inventory/hosts.yml` and `inventory/hosts.yml.example` now include:

```yaml
# External IP configuration for OpenShift worker nodes
rhoso_external_ip_worker_1: "172.21.0.21"  # External IP for worker node 1
rhoso_external_ip_worker_2: "172.21.0.22"  # External IP for worker node 2  
rhoso_external_ip_worker_3: "172.21.0.23"  # External IP for worker node 3
```

#### D. Documentation Updates

- Updated `README.md` with new external IP configuration section
- Updated `SSH-JUMPHOST-GUIDE.md` with external IP examples
- Added variable documentation for worker external IPs

## Usage Instructions

### 1. Default Configuration

The playbooks now provide sensible defaults for worker external IPs:
- Worker 1: `172.21.0.21`
- Worker 2: `172.21.0.22`
- Worker 3: `172.21.0.23`

### 2. Custom Configuration

To use different external IPs, update your `inventory/hosts.yml`:

```yaml
# Custom external IPs for your lab environment
rhoso_external_ip_worker_1: "172.21.0.31"
rhoso_external_ip_worker_2: "172.21.0.32"
rhoso_external_ip_worker_3: "172.21.0.33"
```

### 3. Deployment Process

The updated deployment process now:

1. **Clones repository** with NNCP files containing placeholders
2. **Replaces UUID** with actual lab GUID
3. **Replaces external IP placeholders** with configured IP addresses
4. **Applies NNCP configurations** to OpenShift worker nodes

## Network Configuration Context

### External Network Interface Configuration

The external IPs are used to configure the `enp8s0` interface on each OpenShift worker node:

```yaml
# Example from osp-ng-nncp-w1.yaml
- description: Configuring external enp8s0
  ipv4:
    address:
    - ip: EXTERNAL_IP_WORKER_1  # Gets replaced with actual IP
      prefix-length: 24 
    enabled: true
    dhcp: false
```

### Network Layout

The external network (172.21.0.0/24) is used for:
- External/public OpenStack services
- Floating IP connectivity
- External access to OpenStack APIs

## Benefits

1. **Flexibility**: Labs can now use different external IP ranges
2. **Automation**: No manual sed commands required
3. **Validation**: Ansible can verify IP configurations
4. **Documentation**: Clear mapping between placeholders and actual IPs
5. **Consistency**: Same variable names as used in documentation

## Backward Compatibility

The changes are backward compatible:
- Default IP values are provided if variables are not set
- Existing inventory files will work with defaults
- No changes to deployment command syntax

## Testing

To verify the changes work correctly:

```bash
# Check configuration
./deploy-via-jumphost.sh --check-inventory

# Dry run to see what would be applied
./deploy-via-jumphost.sh --dry-run network-isolation

# Deploy network isolation phase
./deploy-via-jumphost.sh network-isolation
```

The playbooks now fully automate the network isolation setup process as described in the updated documentation, including the new external IP placeholder replacement step.
