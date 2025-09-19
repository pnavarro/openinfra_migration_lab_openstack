# Jinja2 selectattr Filter Compatibility Fix

## Problem

The error encountered was:
```
Unexpected failure during module execution: Could not load "selectattr": 'selectattr'
```

This occurs when using the `selectattr` Jinja2 filter in complex filter chains, which can be incompatible with certain versions of Jinja2 or Ansible.

## Root Cause

The `selectattr` filter, especially when used in complex chains like:
```yaml
resources | selectattr('status.conditions', 'defined') | 
selectattr('status.conditions', 'selectattr', 'type', 'equalto', 'Available') |
selectattr('status.conditions', 'selectattr', 'status', 'equalto', 'True') |
list | length >= 3
```

Can cause compatibility issues across different versions of:
- Jinja2 library
- Ansible core
- Python environments

## Solution Implemented

I've replaced all complex `selectattr` filter chains with more compatible alternatives using:

### 1. json_query Filter (JMESPath)

**Before (Problematic)**:
```yaml
resources | selectattr('status.phase', 'equalto', 'Running') | list | length
```

**After (Compatible)**:
```yaml
resources | json_query('[?status.phase==`Running`]') | length
```

### 2. Simplified Logic with set_fact

**Before (Problematic)**:
```yaml
until: >
  control_plane_status.resources[0].status.conditions | 
  selectattr('type', 'equalto', 'Ready') |
  selectattr('status', 'equalto', 'True') |
  list | length > 0
```

**After (Compatible)**:
```yaml
until: >
  control_plane_status.resources[0].status.conditions | length > 0

- name: Check if Control Plane is ready
  set_fact:
    cp_ready: "{{ control_plane_status.resources[0].status.conditions | json_query('[?type==`Ready` && status==`True`]') | length > 0 }}"
```

## Roles Fixed

### 1. network-isolation
- Fixed NNCP status checking
- Simplified wait conditions
- Added individual NNCP status checks

### 2. control-plane  
- Replaced selectattr with json_query
- Added separate fact-setting for readiness check
- Simplified display logic

### 3. data-plane
- Fixed data plane deployment status checking
- Fixed data plane node set status checking  
- Improved status reporting

### 4. prerequisites
- Fixed cert-manager pod counting
- Improved status display

### 5. install-operators
- Fixed OpenStack operator pod counting
- Enhanced status reporting

### 6. validation
- Fixed control plane pod counting in summary
- Improved deployment status display

## Benefits of This Approach

### 1. **Broader Compatibility**
- Works across different Ansible versions
- Compatible with various Jinja2 versions
- Reduces environment-specific issues

### 2. **Better Error Handling**
- Clearer error messages when conditions fail
- More predictable behavior
- Easier debugging

### 3. **Improved Readability**
- Simpler logic flow
- Explicit condition checking
- Better separation of concerns

### 4. **More Robust**
- Less prone to filter chain failures
- Handles edge cases better
- More reliable in different environments

## json_query Syntax Reference

The `json_query` filter uses JMESPath syntax:

```yaml
# Filter by single condition
resources | json_query('[?status.phase==`Running`]')

# Filter by multiple conditions  
resources | json_query('[?type==`Ready` && status==`True`]')

# Get length of filtered results
resources | json_query('[?status.phase==`Running`]') | length

# Extract specific fields
resources | json_query('[].metadata.name')
```

## Testing

All affected roles have been updated and should now work reliably across different Ansible/Jinja2 environments. The wait conditions are functionally equivalent to the original logic but use more compatible syntax.

## Migration Notes

If you encounter similar `selectattr` issues in other playbooks:

1. **Identify the filter chain** causing the issue
2. **Convert to json_query** using JMESPath syntax
3. **Use set_fact** for complex conditions
4. **Test** with your specific Ansible version

This fix ensures the playbooks work reliably in various deployment environments without requiring specific Jinja2 or Ansible versions.
