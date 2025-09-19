# Subscription Manager Secret Fix

## Problem

The subscription manager secret creation was failing with:
```
Failed to create object: Secret in version "v1" cannot be handled as a Secret: 
json: cannot unmarshal object into Go struct field Secret.stringData of type string
```

## Root Cause Analysis

The error occurred due to two issues:

1. **Empty Credentials**: The `rhc_username` and `rhc_password` variables in the inventory were set to empty strings
2. **stringData vs data Field**: The Kubernetes API was having trouble processing the `stringData` field with JSON content

## User's Working CLI Command

```bash
oc create secret generic subscription-manager \
--from-literal rhc_auth='{"login": {"username": "pnavarro@redhat.com", "password": "1amuntvalencian0!"}}'
```

## Solution Implemented

### 1. Fixed Inventory Credentials

**File:** `inventory/hosts.yml`

**Before:**
```yaml
rhc_username: ""  # Add your Red Hat Customer Portal username
rhc_password: ""  # Add your Red Hat Customer Portal password
```

**After:**
```yaml
rhc_username: "pnavarro@redhat.com"  # Add your Red Hat Customer Portal username
rhc_password: "1amuntvalencian0!"  # Add your Red Hat Customer Portal password
```

### 2. Improved Secret Creation Method

**File:** `roles/data-plane/tasks/main.yml`

**Before (Problematic):**
```yaml
- name: Create subscription manager secret
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: subscription-manager
        namespace: "{{ openstack_namespace }}"
      type: Opaque
      stringData:
        rhc_auth: '{"login": {"username": "{{ subscription_manager_username }}", "password": "{{ subscription_manager_password }}"}}'
```

**After (Fixed):**
```yaml
- name: Create subscription manager authentication JSON
  set_fact:
    rhc_auth_json: '{"login": {"username": "{{ subscription_manager_username }}", "password": "{{ subscription_manager_password }}"}}'
  when: 
    - subscription_manager_username != ""
    - subscription_manager_password != ""

- name: Create subscription manager secret
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: Secret
      metadata:
        name: subscription-manager
        namespace: "{{ openstack_namespace }}"
      type: Opaque
      data:
        rhc_auth: "{{ rhc_auth_json | b64encode }}"
  when: 
    - subscription_manager_username != ""
    - subscription_manager_password != ""
```

## Key Improvements

1. **Two-Step Process**: First create the JSON string as a fact, then use it in the secret
2. **Proper Encoding**: Use `data` field with explicit `b64encode` instead of `stringData`
3. **Better Error Handling**: JSON construction is separated from secret creation
4. **Matches CLI Behavior**: The resulting secret data matches what `oc create secret --from-literal` produces

## Variable Flow

1. `rhc_username` and `rhc_password` (inventory) →
2. `subscription_manager_username` and `subscription_manager_password` (vars/main.yml) →
3. `rhc_auth_json` (task variable) →
4. Base64 encoded as `rhc_auth` in the secret

## Verification

After this fix, the secret should be created successfully with the same content as your working CLI command:
```bash
kubectl get secret subscription-manager -n openstack -o yaml
```

The `rhc_auth` field should contain the base64-encoded JSON authentication data.
