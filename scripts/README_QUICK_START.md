# Quick Start: Multi-Lab RHOSO Deployment

This guide gets you deploying multiple RHOSO labs in under 5 minutes.

## 🚀 TL;DR

```bash
# 1. Create your lab config file (use your actual data)
cat << EOF > my_labs.txt
[Your lab configuration data here]
EOF

# 2. Set up credentials
cp scripts/credentials.yml.example scripts/credentials.yml
# Edit credentials.yml with your Red Hat credentials

# 3. Deploy all labs FROM YOUR LOCAL MACHINE
./scripts/deploy_multiple_labs.sh --credentials scripts/credentials.yml my_labs.txt
```

## 🏗️ **Execution Model**

**Important:** This script now runs **FROM YOUR LOCAL MACHINE** and connects to multiple bastion hosts, just like `deploy-via-jumphost.sh`. This solves Python library dependency issues and follows the original design pattern.

- ✅ **Local Execution**: Runs on your workstation/laptop
- ✅ **Remote Connection**: Connects to multiple bastion hosts via SSH
- ✅ **No Dependencies on Bastion**: No need to install Python libraries on bastion hosts
- ✅ **Parallel Deployment**: Deploys multiple labs simultaneously

## ✅ Prerequisites Check

```bash
# Run this first to verify your environment
./scripts/test_deployment_setup.sh
```

## 📝 Step-by-Step Guide

### Step 1: Prepare Your Lab Configuration

Take the lab configuration data you received (like the example below) and save it to a file:

```
Service	Assigned Email	Details
openshift-cnv.osp-on-ocp-cnv.dev-hjckm	
- unassigned -

Lab UI
https://showroom-showroom.apps.cluster-7h86j.dynamic.redhatworkshops.io/ 
Messages
OpenShift Console: https://console-openshift-console.apps.cluster-7h86j.dynamic.redhatworkshops.io
[... rest of your lab data ...]
```

Save this to a file (e.g., `my_labs.txt`).

### Step 2: Set Up Credentials

```bash
# Copy the template
cp scripts/credentials.yml.example scripts/my_credentials.yml

# Edit with your actual Red Hat credentials
vi scripts/my_credentials.yml
```

Update these fields:
- `registry_username`: Your Red Hat Registry Service Account username
- `registry_password`: Your Red Hat Registry Service Account password/token
- `rhc_username`: Your Red Hat Customer Portal username
- `rhc_password`: Your Red Hat Customer Portal password

### Step 3: Deploy Your Labs

```bash
# Deploy all labs with default settings (3 parallel jobs)
./scripts/deploy_multiple_labs.sh --credentials scripts/my_credentials.yml my_labs.txt

# Or deploy with custom parallelism (recommended for large numbers of labs)
./scripts/deploy_multiple_labs.sh -j 2 --credentials scripts/my_credentials.yml my_labs.txt
```

## 🔍 Monitor Progress

Watch the deployment in real-time:

```bash
# In another terminal, monitor all deployments
tail -f deployment_logs/*.log

# Or monitor just the progress updates
./scripts/deploy_multiple_labs.sh --credentials scripts/my_credentials.yml my_labs.txt | grep PROGRESS
```

## 🛠️ Common Options

```bash
# Dry run (test without making changes)
./scripts/deploy_multiple_labs.sh -d --credentials scripts/my_credentials.yml my_labs.txt

# Deploy only prerequisites for all labs
./scripts/deploy_multiple_labs.sh -p prerequisites --credentials scripts/my_credentials.yml my_labs.txt

# Deploy with verbose output
./scripts/deploy_multiple_labs.sh -v --credentials scripts/my_credentials.yml my_labs.txt

# List labs in your config file
./scripts/deploy_multiple_labs.sh --list my_labs.txt
```

## 📊 Expected Results

After successful deployment:

```
[DEPLOY] Deployment Summary
[INFO] Total labs: 2
[INFO] Completed successfully: 2
[INFO] All deployments completed successfully! 🎉
```

Your generated files will be in:
- `ansible-playbooks/generated_inventories/` - Individual lab inventory files
- `deployment_logs/` - Detailed deployment logs for each lab

## ❗ Troubleshooting

### "Some lab deployments failed"

1. Check the logs:
   ```bash
   grep -i error deployment_logs/*.log
   ```

2. Look at specific failed lab:
   ```bash
   cat deployment_logs/deploy_<failed_lab_guid>_*.log
   ```

3. Test connectivity to a specific lab:
   ```bash
   cd ansible-playbooks
   ansible -i generated_inventories/hosts-cluster-<guid>.yml -m ping all
   ```

### "No valid inventory files found"

Your lab configuration file might have formatting issues:

```bash
# Test the parser directly
python3 scripts/parse_lab_config.py my_labs.txt
```

### "Missing required fields"

Make sure your credentials file is properly formatted:

```bash
# Validate credentials file
python3 -c "import yaml; print(yaml.safe_load(open('scripts/my_credentials.yml')))"
```

## 🎯 Next Steps

After successful deployment:

1. **Access your labs**: Use the URLs from your original lab configuration
2. **Validate deployments**: Run the validation phase:
   ```bash
   ./scripts/deploy_multiple_labs.sh -p validation --credentials scripts/my_credentials.yml my_labs.txt
   ```
3. **Add optional services**: Deploy Heat and Swift if needed:
   ```bash
   ./scripts/deploy_multiple_labs.sh -p optional --credentials scripts/my_credentials.yml my_labs.txt
   ```

## 📚 Full Documentation

For comprehensive documentation, see [`scripts/README.md`](README.md).

## 🆘 Need Help?

1. Run the test suite: `./scripts/test_deployment_setup.sh`
2. Check logs in `deployment_logs/`
3. Review individual lab inventories in `ansible-playbooks/generated_inventories/`
4. Try deploying a single lab manually for debugging

---

**Happy Deploying!** 🚀

