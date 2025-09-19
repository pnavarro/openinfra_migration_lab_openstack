# CRD Availability Improvements - All Operators

## Overview

I've implemented comprehensive CRD (Custom Resource Definition) availability checks across all roles that create custom resources. This ensures that operators have fully deployed their CRDs before we attempt to create instances, preventing timing-related failures.

## Roles Updated

### 1. Prerequisites Role
**Operators**: NMState, MetalLB  
**Resources Created**: NMState, MetalLB instances

**Improvements Added**:
```yaml
# NMState
- name: Wait for NMState CRD to be available
  # Check for nmstates.nmstate.io CRD
- name: Create NMState instance (with retries)
- name: Verify NMState instance is created

# MetalLB  
- name: Wait for MetalLB CRD to be available
  # Check for metallbs.metallb.io CRD
- name: Create MetalLB instance (with retries)
- name: Verify MetalLB instance is created
```

### 2. Control Plane Role
**Operator**: OpenStack Operator  
**Resources Created**: OpenStackControlPlane

**Improvements Added**:
```yaml
- name: Wait for OpenStack Control Plane CRD to be available
  # Check for openstackcontrolplanes.core.openstack.org CRD
- name: Create OpenStack Control Plane (with retries)
```

### 3. Data Plane Role  
**Operator**: OpenStack Operator (DataPlane components)  
**Resources Created**: OpenStackDataPlaneNodeSet, OpenStackDataPlaneDeployment

**Improvements Added**:
```yaml
- name: Wait for OpenStack DataPlane CRDs to be available
  # Check for both:
  # - openstackdataplanenodesets.dataplane.openstack.org
  # - openstackdataplanedeployments.dataplane.openstack.org
- name: Apply data plane resources (with retries)
```

### 4. Network Isolation Role
**Operators**: NMState (NNCP), MetalLB (IPAddressPool, L2Advertisement)  
**Resources Created**: NodeNetworkConfigurationPolicy, IPAddressPool, L2Advertisement

**Improvements Added**:
```yaml
- name: Wait for MetalLB additional CRDs to be available
  # Check for:
  # - ipaddresspools.metallb.io  
  # - l2advertisements.metallb.io
- name: Apply MetalLB resources (with retries)
```

## Consistent Pattern Applied

All roles now follow this consistent pattern:

1. **Wait for Operator Ready**: Ensure CSV status is "Succeeded"
2. **Wait for CRD Available**: Check that required CRDs exist
3. **Create Resource with Retries**: Create custom resource with retry logic
4. **Verify Resource Created**: Confirm the resource was successfully created

## Error Prevention

This prevents these common errors:

### Before (Failed)
```
fatal: [bastion-jumphost]: FAILED! => changed=false
  msg: Failed to find exact match for nmstate.io/v1.NMState by [kind, name, singularName, shortNames]
```

### After (Success)
```
TASK [prerequisites : Wait for NMState CRD to be available] ******************
ok: [bastion-jumphost]

TASK [prerequisites : Create NMState instance] *******************************
changed: [bastion-jumphost]

TASK [prerequisites : Verify NMState instance is created] ********************
ok: [bastion-jumphost]
```

## Dual Implementation

All improvements are implemented in both approaches:

- **`k8s-modules.yml`**: Uses Ansible kubernetes modules (preferred)
- **`oc-native.yml`**: Uses native oc commands (fallback)

Both approaches include identical safety checks and retry logic.

## Benefits

1. **Reliability**: Eliminates timing-related failures
2. **Consistency**: Same pattern across all roles
3. **Debugging**: Clear failure points and status messages
4. **Resilience**: Automatic retries for transient issues
5. **Maintainability**: Predictable behavior across all deployments

## Configuration Options

All CRD checks include configurable parameters:

```yaml
retries: 30        # Wait up to 5 minutes for CRDs
delay: 10          # Check every 10 seconds
resource_retries: 5 # Retry resource creation 5 times
resource_delay: 10  # Wait 10 seconds between retries
```

## Testing

To test the improvements:

```bash
# Test full deployment with enhanced safety
./deploy-via-jumphost.sh

# Test individual phases
./deploy-via-jumphost.sh prerequisites
./deploy-via-jumphost.sh network-isolation
./deploy-via-jumphost.sh control-plane
./deploy-via-jumphost.sh data-plane

# Dry run to verify logic
./deploy-via-jumphost.sh --dry-run full
```

## Monitoring

Each step provides clear output:
- ✅ **CRD available**: "Wait for X CRD to be available - ok"
- ✅ **Resource created**: "Create X instance - changed"  
- ✅ **Verification passed**: "Verify X instance is created - ok"

This comprehensive approach ensures reliable deployment regardless of cluster performance or timing variations.
