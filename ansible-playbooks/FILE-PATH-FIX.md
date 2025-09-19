# File Path Configuration Fix

## Problem

The playbooks were failing with the error:
```
The 'file' lookup had an issue accessing the file '/home/lab-user/labrepo/content/files/nfs-cinder-conf'. file not found
```

## Root Cause

The original playbooks were designed to clone a git repository to access the OpenStack configuration files. However, in our current setup:

1. Files are available locally in `content/files/` directory
2. Some files have been modified (e.g., external IP placeholders replaced)
3. The `labrepo` directory didn't exist, causing file lookup failures

## Solution Implemented

### 1. Updated Variable Configuration

**File:** `vars/main.yml`

**Before:**
```yaml
# Git Repository Configuration
repo_url: "https://github.com/rh-osp-demo/showroom_osp-on-ocp-day2.git"
repo_destination: "labrepo"
files_directory: "{{ repo_destination }}/content/files"
```

**After:**
```yaml
# File Directory Configuration
# Files will be copied to a working directory in the user's home
files_directory: "openstack-files"
```

### 2. Updated install-operators Role

**File:** `roles/install-operators/tasks/main.yml`

**Before:**
```yaml
- name: Clone the lab repository
  ansible.builtin.git:
    repo: "{{ repo_url }}"
    dest: "{{ ansible_env.HOME }}/{{ repo_destination }}"
    version: HEAD
    force: true
```

**After:**
```yaml
- name: Create working directory for OpenStack files
  ansible.builtin.file:
    path: "{{ ansible_env.HOME }}/{{ files_directory }}"
    state: directory
    mode: '0755'

- name: Copy OpenStack configuration files to working directory
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "{{ ansible_env.HOME }}/{{ files_directory }}/{{ item | basename }}"
    mode: '0644'
  loop:
    - "{{ playbook_dir }}/../content/files/osp-ng-nncp-w1.yaml"
    - "{{ playbook_dir }}/../content/files/osp-ng-nncp-w2.yaml"
    # ... (all required files)
    - "{{ playbook_dir }}/../content/files/nfs-cinder-conf"
```

## Benefits

1. **No Git Dependency**: Eliminates the need for external git repository access
2. **Local File Control**: Uses locally available and potentially customized files
3. **Faster Execution**: No network dependency for file access
4. **Better Error Handling**: Clear file copy operations with proper error reporting

## Files Affected

- `vars/main.yml` - Updated file directory configuration
- `roles/install-operators/tasks/main.yml` - Replaced git clone with local file copy
- All other roles continue to work with the same `files_directory` variable

## Verification

The fix ensures that:
- Files are copied from the local `content/files/` directory
- Working directory is created in the user's home (`~/openstack-files/`)
- All subsequent tasks can access files using the same `{{ ansible_env.HOME }}/{{ files_directory }}/filename` pattern
