#!/usr/bin/env python3
"""
Lab Configuration Parser for Multi-Lab Deployment
Parses the lab configuration file and extracts cluster information for deployment.
"""

import re
import yaml
import json
import sys
from typing import Dict, List, Any
from pathlib import Path


class LabConfigParser:
    """Parser for lab configuration data from environment provisioning output."""
    
    def __init__(self, config_file: str):
        """Initialize the parser with the configuration file path."""
        self.config_file = Path(config_file)
        self.labs = []
        
    def parse(self) -> List[Dict[str, Any]]:
        """Parse the configuration file and return list of lab configurations."""
        if not self.config_file.exists():
            raise FileNotFoundError(f"Configuration file not found: {self.config_file}")
            
        content = self.config_file.read_text()
        self.labs = self._extract_lab_configs(content)
        return self.labs
    
    def _extract_lab_configs(self, content: str) -> List[Dict[str, Any]]:
        """Extract lab configurations from the file content."""
        labs = []
        
        # Split content by service entries (looking for service names starting with openshift-cnv)
        service_blocks = re.split(r'^(openshift-cnv\.osp-on-ocp-cnv\.dev-\w+)', content, flags=re.MULTILINE)
        
        # Process each service block (skip the first empty element)
        for i in range(1, len(service_blocks), 2):
            if i + 1 < len(service_blocks):
                service_name = service_blocks[i].strip()
                service_content = service_blocks[i + 1]
                
                lab_config = self._parse_service_block(service_name, service_content)
                if lab_config:
                    labs.append(lab_config)
        
        return labs
    
    def _parse_service_block(self, service_name: str, content: str) -> Dict[str, Any]:
        """Parse a single service block and extract configuration."""
        config = {
            'service_name': service_name,
            'lab_guid': self._extract_guid(service_name),
        }
        
        # Extract basic information
        config.update(self._extract_basic_info(content))
        
        # Extract IP allocation details
        config.update(self._extract_ip_allocation(content))
        
        # Extract YAML data section
        yaml_data = self._extract_yaml_data(content)
        if yaml_data:
            config.update(yaml_data)
        
        return config
    
    def _extract_guid(self, service_name: str) -> str:
        """Extract GUID from service name."""
        match = re.search(r'-(\w+)$', service_name)
        return match.group(1) if match else ''
    
    def _extract_basic_info(self, content: str) -> Dict[str, str]:
        """Extract basic lab information."""
        info = {}
        
        # Extract Lab UI URL
        lab_ui_match = re.search(r'Lab UI\s*\n(https://[^\s]+)', content)
        if lab_ui_match:
            info['lab_ui_url'] = lab_ui_match.group(1)
        
        # Extract OpenShift Console URL
        console_match = re.search(r'OpenShift Console: (https://[^\s]+)', content)
        if console_match:
            info['openshift_console_url'] = console_match.group(1)
        
        # Extract OpenShift API URL
        api_match = re.search(r'OpenShift API for command line \'oc\' client: (https://[^\s]+)', content)
        if api_match:
            info['openshift_api_url'] = api_match.group(1)
        
        # Extract admin password
        admin_pass_match = re.search(r'User admin with password (\S+) is cluster admin', content)
        if admin_pass_match:
            info['openshift_admin_password'] = admin_pass_match.group(1)
        
        # Extract SSH information
        ssh_match = re.search(r'ssh lab-user@(\S+) -p (\d+)', content)
        if ssh_match:
            info['bastion_hostname'] = ssh_match.group(1)
            info['bastion_port'] = ssh_match.group(2)
        
        # Extract SSH password
        ssh_pass_match = re.search(r'Enter ssh password when prompted: (\S+)', content)
        if ssh_pass_match:
            info['bastion_password'] = ssh_pass_match.group(1)
        
        return info
    
    def _extract_ip_allocation(self, content: str) -> Dict[str, str]:
        """Extract IP allocation details."""
        ips = {}
        
        # Extract allocation name and cluster
        alloc_match = re.search(r'Allocation Name: (cluster-\w+)', content)
        if alloc_match:
            ips['allocation_name'] = alloc_match.group(1)
        
        cluster_match = re.search(r'Cluster: (\w+)', content)
        if cluster_match:
            ips['cluster_name'] = cluster_match.group(1)
        
        # Extract network information
        subnet_match = re.search(r'Network Subnet: ([\d.]+/\d+)', content)
        if subnet_match:
            ips['network_subnet'] = subnet_match.group(1)
        
        cidr_match = re.search(r'Network CIDR: ([\d.]+/\d+)', content)
        if cidr_match:
            ips['network_cidr'] = cidr_match.group(1)
        
        # Extract specific IP addresses
        ip_patterns = [
            ('external_ip_worker_1', r'EXTERNAL_IP_WORKER_1=([\d.]+)'),
            ('external_ip_worker_2', r'EXTERNAL_IP_WORKER_2=([\d.]+)'),
            ('external_ip_worker_3', r'EXTERNAL_IP_WORKER_3=([\d.]+)'),
            ('external_ip_bastion', r'EXTERNAL_IP_BASTION=([\d.]+)'),
            ('public_net_start', r'PUBLIC_NET_START=([\d.]+)'),
            ('public_net_end', r'PUBLIC_NET_END=([\d.]+)'),
            ('conversion_host_ip', r'CONVERSION_HOST_IP=([\d.]+)'),
        ]
        
        for key, pattern in ip_patterns:
            match = re.search(pattern, content)
            if match:
                ips[key] = match.group(1)
        
        return ips
    
    def _extract_yaml_data(self, content: str) -> Dict[str, Any]:
        """Extract YAML data section if present."""
        # Look for the Data section which contains YAML
        yaml_match = re.search(r'Data\s*\n(openshift-cnv\.osp-on-ocp-cnv\.dev:.*?)(?=\n\S|\Z)', content, re.DOTALL)
        if yaml_match:
            try:
                yaml_content = yaml_match.group(1)
                # Parse the YAML content
                yaml_data = yaml.safe_load(yaml_content)
                if isinstance(yaml_data, dict) and 'openshift-cnv.osp-on-ocp-cnv.dev' in yaml_data:
                    return yaml_data['openshift-cnv.osp-on-ocp-cnv.dev']
            except yaml.YAMLError as e:
                print(f"Warning: Failed to parse YAML data: {e}")
        
        return {}
    
    def generate_inventory_config(self, lab_config: Dict[str, Any]) -> Dict[str, Any]:
        """Generate Ansible inventory configuration for a lab."""
        inventory = {
            'all': {
                'vars': {
                    # Lab Environment Configuration
                    'lab_guid': lab_config.get('lab_guid', ''),
                    'bastion_user': 'lab-user',
                    'bastion_hostname': lab_config.get('bastion_hostname', ''),
                    'bastion_port': lab_config.get('bastion_port', ''),
                    'bastion_password': lab_config.get('bastion_password', ''),
                    
                    # OpenShift Console
                    'ocp_console_url': lab_config.get('openshift_console_url', ''),
                    'ocp_admin_password': lab_config.get('openshift_admin_password', ''),
                    
                    # Registry credentials (to be filled by user)
                    'registry_username': '',
                    'registry_password': '',
                    
                    # Red Hat Customer Portal credentials (to be filled by user)
                    'rhc_username': '',
                    'rhc_password': '',
                    
                    # Internal lab hostnames
                    'nfs_server_hostname': 'nfsserver',
                    'compute_hostname': 'compute01',
                    
                    # External IP configuration
                    'rhoso_external_ip_worker_1': lab_config.get('external_ip_worker_1', ''),
                    'rhoso_external_ip_worker_2': lab_config.get('external_ip_worker_2', ''),
                    'rhoso_external_ip_worker_3': lab_config.get('external_ip_worker_3', ''),
                    'rhoso_external_ip_bastion': lab_config.get('external_ip_bastion', ''),
                    
                    # Additional network configuration
                    'public_net_start': lab_config.get('public_net_start', ''),
                    'public_net_end': lab_config.get('public_net_end', ''),
                    'conversion_host_ip': lab_config.get('conversion_host_ip', ''),
                    'network_subnet': lab_config.get('network_subnet', ''),
                    'network_cidr': lab_config.get('network_cidr', ''),
                    'allocation_name': lab_config.get('allocation_name', ''),
                    'cluster_name': lab_config.get('cluster_name', ''),
                }
            },
            'bastion': {
                'hosts': {
                    'bastion-jumphost': {
                        'ansible_host': '{{ bastion_hostname }}',
                        'ansible_user': '{{ bastion_user }}',
                        'ansible_port': '{{ bastion_port }}',
                        'ansible_ssh_pass': '{{ bastion_password }}'
                    }
                }
            },
            'nfsserver': {
                'hosts': {
                    'nfs-server': {
                        'ansible_host': '{{ nfs_server_hostname }}',
                        'ansible_user': 'cloud-user',
                        'ansible_ssh_private_key_file': '/home/{{ bastion_user }}/.ssh/{{ lab_guid }}key.pem',
                        'delegate_to': 'bastion-jumphost'
                    }
                }
            },
            'compute_nodes': {
                'hosts': {
                    'compute01': {
                        'ansible_host': '{{ compute_hostname }}',
                        'ansible_user': 'cloud-user',
                        'ansible_ssh_private_key_file': '/home/{{ bastion_user }}/.ssh/{{ lab_guid }}key.pem',
                        'delegate_to': 'bastion-jumphost'
                    }
                }
            }
        }
        
        return inventory
    
    def save_inventory_files(self, output_dir: str = "generated_inventories") -> List[str]:
        """Save inventory files for all parsed labs."""
        output_path = Path(output_dir)
        output_path.mkdir(exist_ok=True)
        
        inventory_files = []
        
        for lab_config in self.labs:
            lab_guid = lab_config.get('lab_guid', 'unknown')
            filename = f"hosts-cluster-{lab_guid}.yml"
            filepath = output_path / filename
            
            inventory = self.generate_inventory_config(lab_config)
            
            # Create YAML content with comments
            yaml_content = f"""---
# Ansible inventory for RHOSO deployment on cluster-{lab_guid} via SSH jump host (bastion)
# Generated automatically from lab configuration data

"""
            yaml_content += yaml.dump(inventory, default_flow_style=False, sort_keys=False)
            
            filepath.write_text(yaml_content)
            inventory_files.append(str(filepath))
            
            print(f"Generated inventory file: {filepath}")
        
        return inventory_files


def main():
    """Main function for command-line usage."""
    if len(sys.argv) != 2:
        print("Usage: python3 parse_lab_config.py <lab_config_file>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    
    try:
        parser = LabConfigParser(config_file)
        labs = parser.parse()
        
        print(f"Parsed {len(labs)} lab configurations:")
        for lab in labs:
            print(f"  - Lab GUID: {lab.get('lab_guid', 'N/A')}")
            print(f"    Service: {lab.get('service_name', 'N/A')}")
            print(f"    Bastion: {lab.get('bastion_hostname', 'N/A')}:{lab.get('bastion_port', 'N/A')}")
            print()
        
        # Generate inventory files
        inventory_files = parser.save_inventory_files()
        print(f"\nGenerated {len(inventory_files)} inventory files in 'generated_inventories' directory")
        
        # Save lab summary as JSON
        summary_file = Path("generated_inventories/lab_summary.json")
        summary_file.write_text(json.dumps(labs, indent=2))
        print(f"Lab summary saved to: {summary_file}")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

