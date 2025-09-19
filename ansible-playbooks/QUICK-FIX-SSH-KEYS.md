# Quick Fix for SSH Key Issues

## Problem
The SSH key error shows:
```
Warning: Identity file /home/lab-user/.ssh/s7ffskey.pem not accessible: No such file or directory.
no such identity: /home/lab-user/.ssh/bastion_5s4wg: No such file or directory
```

This indicates a GUID mismatch between your inventory (`s7ffs`) and the actual SSH keys on the bastion.

## Quick Fix Steps

### Option 1: Use the Automated Script

Run the provided script to detect and fix the GUID automatically:

```bash
./check-ssh-keys.sh
```

This will:
- Check what SSH keys actually exist on the bastion
- Detect the correct GUID from the key filenames
- Update your inventory automatically
- Test the keys

### Option 2: Manual Fix

If you prefer to fix it manually:

#### Step 1: Check what SSH keys exist on the bastion

```bash
ssh -p 31378 lab-user@ssh.ocpvdev01.rhdp.net 'ls -la ~/.ssh/*.pem'
```

#### Step 2: Look for a pattern like `{guid}key.pem`

You should see something like:
- `5s4wgkey.pem` (if your real GUID is `5s4wg`)
- Or `s7ffskey.pem` (if that's the correct one)

#### Step 3: Update your inventory

Edit `inventory/hosts.yml` and change the `lab_guid` line:

```yaml
# Change from:
lab_guid: "s7ffs"

# To (use the GUID from the actual key file):
lab_guid: "5s4wg"  # or whatever GUID matches your key file
```

#### Step 4: Test the fix

```bash
# Test SSH connectivity to verify the fix
./test-ssh-connectivity.sh

# If successful, run the deployment
./deploy-via-jumphost.sh nfs-server
```

## Expected Key File Pattern

The SSH key should be named: `{lab-guid}key.pem`

Examples:
- Lab GUID `5s4wg` → Key file `/home/lab-user/.ssh/5s4wgkey.pem`
- Lab GUID `s7ffs` → Key file `/home/lab-user/.ssh/s7ffskey.pem`

## Verification

After fixing the GUID, you should be able to test SSH manually:

```bash
# SSH to bastion first
ssh -p 31378 lab-user@ssh.ocpvdev01.rhdp.net

# Then from bastion, test the key
ssh -i ~/.ssh/{correct-guid}key.pem cloud-user@nfsserver
ssh -i ~/.ssh/{correct-guid}key.pem cloud-user@compute01
```

Both should work without password prompts.

## Common Issues

1. **Key file doesn't exist**: The lab may not be fully provisioned yet
2. **Permission denied**: The key may not be authorized on the target hosts
3. **Wrong GUID**: Multiple lab environments may cause GUID confusion

Run the automated script first - it will detect and fix most of these issues automatically.
