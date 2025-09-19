# Troubleshooting SSH Delegation Issues

## Problem

You might encounter SSH delegation errors like this when running roles that need to connect to internal lab resources:

```
TASK [nfs-server : Create NFS directories] ********************************
[WARNING]: Unhandled error in Python interpreter discovery for host bastion-jumphost: 
Failed to connect to the host via ssh: ssh: Could not resolve hostname nfsserver: Name or service not known
failed: [bastion-jumphost -> nfsserver] (item=/nfs/cinder) =>
  msg: |-
    Data could not be sent to remote host "nfsserver". Make sure this host can be reached over ssh: 
    ssh: Could not resolve hostname nfsserver: Name or service not known
  unreachable: true
```

## Root Cause

This error occurs because Ansible's `delegate_to` functionality attempts to establish SSH connections directly from your workstation to the internal lab resources (like `nfsserver`, `compute01`) instead of going through the bastion host as intended.

The internal hostnames like `nfsserver` and `compute01` are only resolvable from within the lab environment (on the bastion), not from your external workstation.

## Solution Implemented

I've updated the affected roles to use direct SSH commands executed on the bastion instead of Ansible's delegation mechanism:

### Before (Failed)
```yaml
- name: Configure compute node
  delegate_to: "{{ compute_hostname }}"
  become: true
  vars:
    ansible_ssh_private_key_file: "/home/{{ bastion_user }}/.ssh/{{ guid }}key.pem"
    ansible_user: "cloud-user"
  block:
    - name: Set hostname
      ansible.builtin.hostname:
        name: "{{ compute_nodes[0].hostname }}"
```

### After (Working)
```yaml
- name: Set hostname for compute node via SSH
  shell: |
    ssh -i /home/{{ bastion_user }}/.ssh/{{ guid }}key.pem -o StrictHostKeyChecking=no cloud-user@{{ compute_hostname }} "sudo hostnamectl set-hostname {{ compute_nodes[0].hostname }}"
  register: hostname_result
  changed_when: true
```

## Roles Updated

### 1. NFS Server Role (`roles/nfs-server/tasks/main.yml`)

**Fixed Operations**:
- Create NFS directories
- Configure NFS exports
- Set up networking
- Start NFS services
- Verify configuration

**New Approach**: All operations use `ssh` commands executed from the bastion.

### 2. Data Plane Role (`roles/data-plane/tasks/main.yml`)

**Fixed Operations**:
- Set compute node hostname
- Configure network interfaces (eth0, eth1)
- Activate network connections

**New Approach**: Network configuration via SSH commands instead of nmcli module delegation.

## Benefits of This Approach

### 1. Proper Network Flow
```
Your Workstation → Bastion → Internal Resources
     Ansible     →   SSH   →   SSH commands
```

### 2. Simplified Connectivity
- No complex delegation configuration needed
- Uses the same SSH keys that work manually
- Respects the lab's network topology

### 3. Debugging Friendly
- SSH commands are visible in the output
- Can be tested manually for troubleshooting
- Clear error messages when issues occur

### 4. Consistent Behavior
- Works the same way as manual SSH access
- Uses the same authentication method
- Follows the documented connectivity pattern

## Verification

### Automated Testing

Use the provided test script to verify SSH connectivity:

```bash
# Run the connectivity test script (works from your workstation or bastion)
./test-ssh-connectivity.sh
```

This script will:
- 🔍 **Auto-detect** if you're running from workstation or bastion
- ✅ **Test bastion connectivity** (if running from workstation)
- ✅ **Test SSH to NFS server** (`nfsserver`)
- ✅ **Test SSH to compute node** (`compute01`)
- ✅ **Test sudo access** on both nodes
- ✅ **Verify SSH key usage** and paths

### Manual Testing

You can also verify manually by checking SSH connectivity:

```bash
# Test NFS server connectivity
ssh -i /home/lab-user/.ssh/s7ffskey.pem cloud-user@nfsserver

# Test compute node connectivity  
ssh -i /home/lab-user/.ssh/s7ffskey.pem cloud-user@compute01
```

If these work from the bastion, the Ansible playbooks will also work.

## Configuration Notes

The SSH commands include several important options:

- `-i /home/{{ bastion_user }}/.ssh/{{ guid }}key.pem` - Uses the lab-provided SSH key
- `-o StrictHostKeyChecking=no` - Skips host key verification (safe in lab environment)
- `cloud-user@{{ hostname }}` - Uses the correct username for lab VMs
- `sudo` prefix for privileged operations

## Error Prevention

This approach prevents these common issues:

1. **Hostname resolution failures** - Commands run from bastion where hostnames resolve
2. **Network connectivity issues** - Uses the established lab network paths
3. **Authentication problems** - Uses the same SSH keys that work manually
4. **Privilege escalation issues** - Explicit sudo usage where needed

## Testing

To test the fixes:

```bash
# Test NFS server configuration
./deploy-via-jumphost.sh nfs-server

# Test data plane configuration
./deploy-via-jumphost.sh data-plane

# Run with verbose output for debugging
./deploy-via-jumphost.sh --verbose nfs-server
```

The playbooks now properly execute all SSH operations through the bastion host, matching the manual connectivity pattern that works in the lab environment.
