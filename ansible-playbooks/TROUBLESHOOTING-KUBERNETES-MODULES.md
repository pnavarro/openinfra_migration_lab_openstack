# Troubleshooting Kubernetes Module Issues

## Problem

You might encounter an error like this when running the prerequisites role:

```
TASK [prerequisites : Verify OpenShift cluster access] ********************
fatal: [bastion-jumphost]: FAILED! => changed=false
  msg: Failed to import the required Python library (kubernetes) on bastion's Python /usr/bin/python3. 
  Please read the module documentation and install it in the appropriate location.
```

## Root Cause

This error occurs when the Python `kubernetes` library is not installed on the bastion host, which is required for Ansible's `kubernetes.core` modules to work.

## Solutions Implemented

The updated playbooks now include multiple fallback mechanisms:

### 1. Automatic Python Library Installation

The prerequisites role now attempts to install the required libraries:

```yaml
- name: Install Python kubernetes library using pip3
- name: Install Python kubernetes library using pip (fallback)
- name: Try installing kubernetes library via dnf/yum (RHEL fallback)
```

### 2. Fallback to Native oc Commands

If the Python libraries cannot be installed or don't work, the playbooks automatically fall back to using native `oc` commands instead of Ansible's kubernetes modules.

### 3. Dual Approach Architecture

The prerequisites role now uses two separate task files:
- `k8s-modules.yml` - Uses Ansible kubernetes modules (preferred)
- `oc-native.yml` - Uses native oc commands (fallback)

## Manual Solutions

If the automatic solutions don't work, you can manually install the libraries on the bastion:

### Option 1: Using pip3

```bash
# On the bastion host
sudo pip3 install kubernetes openshift
```

### Option 2: Using package manager

```bash
# On RHEL/CentOS systems
sudo dnf install python3-kubernetes python3-openshift

# On Ubuntu/Debian systems  
sudo apt-get install python3-kubernetes python3-openshift
```

### Option 3: Force use of oc commands only

If you prefer to only use oc commands, you can modify the playbook to skip the kubernetes module test:

```yaml
# In the prerequisites role main.yml, change:
- name: Test kubernetes module availability
  kubernetes.core.k8s_info:
    api_version: v1
    kind: Node
  register: k8s_test
  ignore_errors: true

# To:
- name: Force use of oc commands
  set_fact:
    k8s_test:
      failed: true
```

## Verification

After the fix, you should see either:

1. **Success with kubernetes modules:**
   ```
   TASK [prerequisites : Use kubernetes modules if available]
   included: /path/to/k8s-modules.yml
   ```

2. **Success with oc fallback:**
   ```
   TASK [prerequisites : Fallback to oc commands if kubernetes modules fail]
   included: /path/to/oc-native.yml
   ```

Both approaches will achieve the same result - installing the required operators.

## Benefits of This Approach

- **Resilient**: Works regardless of Python library availability
- **Automatic**: No manual intervention required in most cases
- **Transparent**: Same end result regardless of which method is used
- **Maintainable**: Both approaches are kept in sync

## Testing

To test the fallback mechanism:

```bash
# Test with current setup
./deploy-via-jumphost.sh --dry-run prerequisites

# Test with verbose output
./deploy-via-jumphost.sh --verbose prerequisites
```

The playbooks will automatically choose the best available method and provide clear output about which approach is being used.
