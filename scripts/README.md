# AWX Node Selector Configuration Script

This directory contains scripts for configuring AWX to run jobs on specific OpenShift nodes based on network connectivity requirements.

## configure-awx-node-selector.sh

### Purpose
This script automatically configures AWX to run migration jobs on the OpenShift node that has network connectivity to the RHOSO conversion host. This is essential for migration scenarios where only specific nodes can reach the source OpenStack environment.

### How it works
1. **Node Discovery**: Gets all OpenShift nodes in the cluster
2. **Connectivity Testing**: Tests SSH connectivity from each node to the conversion host
3. **Node Selection**: Identifies the first node that can reach the conversion host
4. **AWX Configuration**: Updates the AWX instance group with a nodeSelector to restrict job execution to the accessible node

### Prerequisites
- OpenShift CLI (`oc`) installed and configured
- `kubectl` installed
- `jq` installed for JSON processing
- `curl` for AWX API calls
- Logged into the OpenShift cluster (`oc login`)
- AWX deployed in the cluster with admin credentials accessible

### Usage

```bash
# Basic usage
./configure-awx-node-selector.sh <rhoso_conversion_host_ip>

# Example
./configure-awx-node-selector.sh 192.168.2.26
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AWX_NAMESPACE` | `awx` | Namespace where AWX is deployed |
| `INSTANCE_GROUP_NAME` | `default` | AWX instance group to configure |
| `SSH_PORT` | `22` | SSH port to test connectivity |
| `TIMEOUT` | `5` | Connection timeout in seconds |

### Examples

```bash
# Use custom AWX namespace
AWX_NAMESPACE=automation ./configure-awx-node-selector.sh 192.168.2.26

# Configure specific instance group
INSTANCE_GROUP_NAME=migration ./configure-awx-node-selector.sh 192.168.2.26

# Use custom SSH port and timeout
SSH_PORT=2222 TIMEOUT=10 ./configure-awx-node-selector.sh 192.168.2.26
```

### What the script does

1. **Validates input**: Checks IP address format and prerequisites
2. **Tests connectivity**: Uses `oc debug node/` to test SSH connectivity from each node
3. **Finds accessible node**: Identifies the first node that can reach the conversion host
4. **Updates AWX**: Configures the instance group with nodeSelector:
   ```yaml
   spec:
     nodeSelector:
       kubernetes.io/hostname: <accessible-node-name>
   ```
5. **Verifies configuration**: Confirms the update was successful

### Output Example

```
[INFO] Starting AWX nodeSelector configuration for conversion host: 192.168.2.26

[INFO] Checking prerequisites...
[SUCCESS] Prerequisites check passed

[INFO] Getting OpenShift nodes...
[SUCCESS] Found 3 OpenShift nodes

[INFO] Testing SSH connectivity from all nodes to 192.168.2.26...
[INFO] Testing SSH connectivity from node: control-plane-cluster-zkp7c-1 to 192.168.2.26:22
[SUCCESS] Node control-plane-cluster-zkp7c-1 can reach 192.168.2.26:22
[SUCCESS] Found accessible node: control-plane-cluster-zkp7c-1

[INFO] Getting AWX admin password...
[INFO] Getting AWX service URL...
[SUCCESS] AWX URL: https://awx-awx.apps.cluster.example.com

[INFO] Updating AWX instance group 'default' with nodeSelector for node: control-plane-cluster-zkp7c-1
[INFO] Found instance group 'default' with ID: 1
[SUCCESS] Successfully updated AWX instance group 'default' with nodeSelector for node: control-plane-cluster-zkp7c-1

[INFO] Verifying AWX instance group configuration...
[SUCCESS] Configuration verified: AWX jobs will run on node control-plane-cluster-zkp7c-1

Instance group configuration:
spec:
  nodeSelector:
    kubernetes.io/hostname: control-plane-cluster-zkp7c-1

[SUCCESS] AWX configuration completed successfully!
[INFO] All AWX jobs in the 'default' instance group will now run on node: control-plane-cluster-zkp7c-1
```

### Troubleshooting

#### Common Issues

1. **No nodes can reach conversion host**
   - Check network connectivity and routing
   - Verify firewall rules
   - Ensure conversion host SSH service is running

2. **AWX API errors**
   - Verify AWX is running and accessible
   - Check AWX admin credentials
   - Ensure proper RBAC permissions

3. **OpenShift connectivity issues**
   - Ensure `oc login` was successful
   - Check cluster connectivity
   - Verify node access permissions

#### Debug Mode

Add `set -x` at the beginning of the script for detailed execution logging:

```bash
# Edit the script to add debug mode
sed -i '2a set -x' configure-awx-node-selector.sh
```

### Security Considerations

- The script uses AWX admin credentials stored in OpenShift secrets
- SSH connectivity testing is non-intrusive (only tests port connectivity)
- No sensitive data is logged or stored
- AWX API calls use HTTPS with proper authentication

### Integration with Migration Workflows

This script should be run before starting migration jobs to ensure they execute on nodes with proper network connectivity to the source environment.
