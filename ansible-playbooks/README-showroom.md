# Showroom Configuration

This directory contains an independent playbook and script to configure the Showroom Git repository URL via SSH jump host.

## Files

- `configure-showroom.yml` - Ansible playbook to set the GIT_REPO_URL environment variable
- `configure-showroom.sh` - Shell script wrapper for easy execution
- `README-showroom.md` - This documentation file

## Purpose

The playbook executes the following OpenShift command via the bastion host:

```bash
oc set env deployment/showroom -n showroom GIT_REPO_URL=https://github.com/pnavarro/openinfra_migration_lab_openstack
```

## Usage

### Using the Shell Script (Recommended)

```bash
# Configure showroom for cluster-7m9ft
./configure-showroom.sh -i inventory/hosts-cluster-7m9ft.yml

# Configure with custom repository URL
./configure-showroom.sh -i inventory/hosts-cluster-7h86j.yml -r https://github.com/myuser/my-repo

# Dry run to see what would be changed
./configure-showroom.sh -i inventory/hosts-cluster-6hwf7.yml --dry-run

# Verbose output
./configure-showroom.sh -i inventory/hosts.yml -v
```

### Using Ansible Directly

```bash
# Basic execution
ansible-playbook -i inventory/hosts-cluster-7m9ft.yml configure-showroom.yml

# With custom variables
ansible-playbook -i inventory/hosts-cluster-7h86j.yml configure-showroom.yml \
  -e showroom_git_repo_url=https://github.com/myuser/my-repo \
  -e showroom_namespace=showroom \
  -e showroom_deployment=showroom

# Dry run
ansible-playbook -i inventory/hosts-cluster-6hwf7.yml configure-showroom.yml --check
```

## Configuration Variables

The playbook supports the following variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `showroom_git_repo_url` | `https://github.com/pnavarro/openinfra_migration_lab_openstack` | Git repository URL to set |
| `showroom_namespace` | `showroom` | Kubernetes namespace where showroom is deployed |
| `showroom_deployment` | `showroom` | Name of the showroom deployment |

## Prerequisites

1. **Showroom must be deployed** - The playbook will check for the existence of the namespace and deployment
2. **OpenShift access** - The bastion host must have `oc` client configured and authenticated
3. **Ansible inventory** - Use one of the provided inventory files for your cluster

## What the Playbook Does

1. **Verifies OpenShift access** - Checks that `oc` commands work
2. **Checks namespace existence** - Ensures the showroom namespace exists
3. **Checks deployment existence** - Ensures the showroom deployment exists
4. **Sets environment variable** - Updates the GIT_REPO_URL environment variable
5. **Verifies the change** - Confirms the environment variable is set correctly
6. **Waits for rollout** - Ensures the deployment rollout completes successfully

## Error Handling

The playbook includes comprehensive error handling:

- **Missing namespace** - Warns if the showroom namespace doesn't exist
- **Missing deployment** - Warns if the showroom deployment doesn't exist
- **OpenShift connectivity** - Fails if unable to connect to OpenShift
- **Rollout verification** - Ensures the deployment update completes successfully

## Examples for Each Cluster

```bash
# For cluster-7m9ft
./configure-showroom.sh -i inventory/hosts-cluster-7m9ft.yml

# For cluster-7h86j
./configure-showroom.sh -i inventory/hosts-cluster-7h86j.yml

# For cluster-6hwf7
./configure-showroom.sh -i inventory/hosts-cluster-6hwf7.yml
```

## Troubleshooting

### Common Issues

1. **"Namespace does not exist"**
   - Ensure showroom is deployed in your cluster
   - Check the namespace name with: `oc get namespaces | grep showroom`

2. **"Deployment does not exist"**
   - Verify showroom deployment: `oc get deployments -n showroom`
   - Check if the deployment name is different from 'showroom'

3. **"Permission denied"**
   - Ensure your OpenShift user has permissions to modify deployments
   - Check current user: `oc whoami`

4. **SSH connection issues**
   - Verify bastion connectivity in your inventory file
   - Test SSH access: `ssh lab-user@ssh.ocpvdev01.rhdp.net -p <port>`

### Debug Mode

Run with verbose output to see detailed execution:

```bash
./configure-showroom.sh -i inventory/hosts-cluster-7m9ft.yml -v
```

Or use Ansible's debug mode:

```bash
ansible-playbook -i inventory/hosts-cluster-7m9ft.yml configure-showroom.yml -vvv
```
