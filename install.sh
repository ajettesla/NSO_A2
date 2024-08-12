#!/bin/bash

openrc_file=$1
tag=$2
sshkey=$3

if [ -z "$4" ]; then
    nofn=3
else 
    nofn=$4
fi


# Check if the OpenRC file exists
if [ ! -f "$openrc_file" ]; then
    echo " $(date +%T ) Error: OpenRC file '$openrc_file' not found."
    exit 1
fi

# Source the OpenRC file
source "$openrc_file"

# Check if the OpenStack CLI command is available and working
openstack flavor list > /dev/null 2>&1;

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Connected to OpenStack cloud ."
else
    echo " $(date +%T ) Failed to connect to OpenStack cloud."
    exit 1
fi

openstack keypair create ${sshkey} > ${sshkey}.pem

if [ $? -eq 0 ];then 
    echo " $(date +%T ) ssh key is generate "
    chmod 600 ${sshkey}.pem
else
    echo " $(date +%T ) Falied to create ssh key"
    exit 1
fi

openstack network create vrundhavan_public --tag ${tag}network_public 1>/dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Public network is created."
else
    echo " $(date +%T ) Fail to create Public network"
    exit 1
fi


openstack network create vrundhavan_private --tag ${tag}network_private 1>/dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Private network is created."
else
    echo " $(date +%T ) Fail to create Private network"
    exit 1
fi

openstack subnet create --dhcp --network vrundhavan_public --subnet-range 10.1.1.0/24 public_subnet --tag ${tag}subnet_public 1>/dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Public subnet is created."
else
    echo " $(date +%T ) Fail to create public subnet"
    exit 1
fi

openstack subnet create --dhcp --network vrundhavan_private --subnet-range 10.1.2.0/24 private_subnet --tag ${tag}subnet_private 1>/dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Private subnet is created."
else
    echo " $(date +%T ) Fail to create Private subnet"
    exit 1
fi

openstack security group create external_security_group --tag ${tag}security_group_external 1>/dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) External security group is created."
else
    echo " $(date +%T ) Fail to create External security group"
    exit 1
fi

openstack security group create internal_security_group --tag ${tag}security_group_internal 1>/dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Internal security group is created."
else
    echo " $(date +%T ) Fail to create Internal security group"
    exit 1
fi

openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 22 --protocol tcp --ingress external_security_group 1>/dev/null
openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 80 --protocol tcp --ingress external_security_group 1>/dev/null
openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 9090 --protocol tcp --ingress external_security_group 1>/dev/null
openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 3000 --protocol tcp --ingress external_security_group 1>/dev/null
openstack security group rule create --remote-ip 10.1.0.0/16 --protocol any --ingress external_security_group 2>&1 > /dev/null
openstack security group rule create --remote-ip 0.0.0.0/0 --dst-port 161 --protocol udp --ingress external_security_group 1>/dev/null
openstack security group rule create --remote-ip 0.0.0.0/0 --protocol icmp --ingress external_security_group 1>/dev/null


openstack security group rule create --remote-ip 10.1.0.0/16 --protocol any --ingress internal_security_group 2>&1 > /dev/null

echo " $(date +%T ) security group have rule's now"

openstack router create router_1 --tag ${tag}router_1 1>/dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Router is created ."
else
    echo " $(date +%T ) Fail to create Router"
    exit 1
fi

openstack router set --external-gateway ext-net router_1 1>/dev/null


if [ $? -eq 0 ]; then
    echo " $(date +%T ) set external-gateway to router is ."
else
    echo " $(date +%T ) Fail to set external-gateway to router"
    exit 1
fi


openstack router add subnet router_1 private_subnet 1>/dev/null

openstack router add subnet router_1 public_subnet 1>/dev/null

echo " $(date +%T ) subnet are added to router's"


floating_ip_bastion=$(openstack floating ip create --tag ${tag}bastion_ip ext-net -f json | jq -r .name) 

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Floating IP for bastion is create $floating_ip_bastion"
else
    echo " $(date +%T ) Fail to create bastion floating IP"
    exit 1
fi


floating_ip_haproxy=$(openstack floating ip create --tag ${tag}haproxy_ip ext-net -f json | jq -r .name) 

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Floating IP for haproxy is create $floating_ip_haproxy"
    sed -i "s/^floatingIp=.*/floatingIp=$floating_ip_haproxy/" dcollect.sh
else
    echo " $(date +%T ) Fail to create haproxy floating IP"
    exit 1
fi


export image_name='Ubuntu 22.04 Jammy Jellyfish x86_64'

export flavor_name='m1.small'

if [ -z "$image_name" ] || [ -z "$flavor_name" ] || [ -z "$sshkey" ] || [ -z "$tag" ]; then
    echo " $(date +%T ) Required environment variables are not set."
    exit 1
fi

openstack server create --os-compute-api-version 2.52 --image "$image_name" --flavor "$flavor_name" --network vrundhavan_public --key-name ${sshkey} --security-group external_security_group  -f json --tag ${tag}bastion Bastion  2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Bastion machine is create "
else
    echo " $(date +%T ) Fail to create bastion"
    exit 1
fi

openstack server create --os-compute-api-version 2.52 --image "$image_name" --flavor "$flavor_name" --network vrundhavan_public --key-name ${sshkey} --security-group external_security_group  -f json --tag ${tag}proxy_machine proxy_1 2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) proxy machine is create "
else
    echo " $(date +%T ) Fail to create proxy"
    exit 1
fi


openstack server create --os-compute-api-version 2.52 --image "$image_name" --flavor "$flavor_name" --network vrundhavan_public --key-name ${sshkey} --security-group external_security_group  -f json --tag ${tag}proxy_machine proxy_2 2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) proxy machine is create "
else
    echo " $(date +%T ) Fail to create proxy"
    exit 1
fi

openstack server add floating ip Bastion $floating_ip_bastion 2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) Bastion have public ip now "
else
    echo " $(date +%T ) Fail to assign public ip to bastion"
    exit 1
fi


openstack server add floating ip proxy_1 $floating_ip_haproxy 2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) proxy_1 as master have public ip now "
else
    echo " $(date +%T ) Fail to assign public ip to proxy_1"
    exit 1
fi

for x in $(seq 1 $nofn); do

  openstack server create --os-compute-api-version 2.52 --image "$image_name" --flavor "$flavor_name" --network vrundhavan_private --key-name "$sshkey" --security-group internal_security_group -f json --tag "${tag}dev" dev_"$x"  1>/dev/null

  if [ $? -eq 0 ]; then
      echo " $(date +%T ) dev${x} is created "
  else   
      echo " $(date +%T ) Fail to create dev"
      exit 1
  fi
done


# File where the inventory will be written
inventory_file="openstack_inventory"

# Remove the old inventory file if it exists
rm -f "$inventory_file"

# Start writing the inventory file

grep -q "bastion" /etc/hosts

if [ $? -eq 0 ]; then
    # If "bastion" exists, replace the line with the new IP and hostname
    sudo sed -i "/bastion/c\\$floating_ip_bastion bastion" /etc/hosts
else
    # If "bastion" does not exist, add the new IP and hostname to the file
    echo "$floating_ip_bastion bastion" | sudo tee -a /etc/hosts > /dev/null
fi

grep -q "proxy" /etc/hosts

if [ $? -eq 0 ]; then
    # If "bastion" exists, replace the line with the new IP and hostname
    sudo sed -i "/proxy/c\\$floating_ip_haproxy bastion" /etc/hosts
else
    # If "bastion" does not exist, add the new IP and hostname to the file
    echo "$floating_ip_haproxy haproxy" | sudo tee -a /etc/hosts > /dev/null
fi


# Temporary files for storing device names
dev_file=$(mktemp)
proxy_file=$(mktemp)
bastion_file=$(mktemp)


# Define filenames
dev_file="dev_inventory.tmp"
proxy_file="proxy_inventory.tmp"
bastion_file="bastion_inventory.tmp"

dev_file="dev_inventory.tmp"
proxy_file="proxy_inventory.tmp"
bastion_file="bastion_inventory.tmp"
inventory_file="openstack_inventory"

# Clear previous temporary files
> "$dev_file"
> "$proxy_file"
> "$bastion_file"

# Fetch the list of servers in JSON format
servers_json=$(openstack server list -f json)

# Process each server dictionary
echo "$servers_json" | jq -c '.[]' | while IFS= read -r server; do
  # Extract values
  id=$(echo "$server" | jq -r .ID)
  value=$(openstack server show "$id" -f json)

  name=$(echo "$value" | jq -r '.name')
  # Note: Updated jq command to handle multiple IP addresses correctly

  tags=$(echo "$value" | jq -r '.tags[]' 2>/dev/null || echo "")

  # Check for 'dev', 'proxy', or 'bastion' tags and write to appropriate section
  addresses=$(echo "$value" | jq -r '.addresses | to_entries[] | .value[0]')
 if [[ "$tags" == *"dev"* ]]; then
    if [[ -n "$addresses" ]]; then
        echo "$name ansible_host=$addresses ansible_ssh_private_key_file=${sshkey}.pem" >> "$dev_file"
    else
        sleep 2
        address=$(openstack server show $id |grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')
        if [[ -n $address ]]; then
            echo "$name ansible_host=$address ansible_ssh_private_key_file=${sshkey}.pem" >> "$dev_file"
        else
            echo $(openstack server show $id)
            echo "Something wrong with the address for $name. Values received: $addresses"
        fi
    fi
  elif [[ "$tags" == *"proxy"* ]]; then
    if [[ -n "$addresses" ]]; then
        echo "$name ansible_host=$addresses ansible_ssh_private_key_file=${sshkey}.pem" >> "$proxy_file"
    else
        echo "Something wrong with the address for $name. Values received: $addresses"
    fi
  elif [[ "$tags" == *"bastion"* ]]; then
    # Handle case where there may be multiple IP addresses
    addresses=$(echo "$value" | jq -r '.addresses | to_entries[] | .value[1] // empty' | head -n 1)
    if [[ -n "$addresses" ]]; then
        echo "$name ansible_host=$addresses ansible_ssh_private_key_file=${sshkey}.pem" >> "$bastion_file"
    else
        echo "Something wrong with the address for $name. Values received: $addresses"
    fi
  fi
done

# Create inventory file
{
  echo "[local]"
  echo "localhost ansible_connection=local"
  echo "[dev]"
  cat "$dev_file"
  echo "[proxy]"
  cat "$proxy_file"
  echo "[bastion]"
  cat "$bastion_file"
} > "$inventory_file"

# Clean up temporary files
rm -f "$dev_file" "$proxy_file" "$bastion_file"

# Append device details to inventory file
rm -rf NSO_final_project

git clone https://github.com/ajettesla/NSO_final_project.git > /dev/null

echo "repository was cloned"

cp ${sshkey}.pem NSO_final_project/

rm -rf NSO_final_project/environments/prod

# Cleanup temporary files
rm -f "$dev_file" "$proxy_file"

# Append groupings
{
  echo -e "\n"
  echo "[all:children]"
  echo -e "\n"
  echo "proxy"
  echo "dev"
} >> "$inventory_file"

echo " $(date +%T) Inventory file generated: $inventory_file"

cp "$inventory_file" NSO_final_project/environments/prod

mkdir -p NSO_final_project/group_vars

cat <<EOF > NSO_final_project/group_vars/all.yml

floatingIp:
  bastion: $floating_ip_bastion
  haproxy: $floating_ip_haproxy

prometheus:
    version: 2.54.0-rc.1
    install_dir: "/opt/prometheus"
    data_dir: "/var/lib/prometheus"
    config_dir: "/etc/prometheus"
    prometheus_binary_url: "https://github.com/prometheus/prometheus/releases/download/v2.54.0-rc.1/prometheus-2.54.0-rc.1.linux-amd64.tar.gz"
    node_exporter_binary_url: "https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz"

EOF

chmod 600 NSO_final_project/${sshkey}.pem > /dev/null 2>&1

rm -rf NSO_final_project/roles/ansible/files/NSO_final_project.zip > /dev/null 2>&1

zip -r NSO_final_project/roles/ansible/files/NSO_final_project.zip NSO_final_project > /dev/null 2>&1

mkdir NSO_final_project/roles/keepalived/files > /dev/null 2>&1

cp openrc_file  NSO_final_project/roles/keepalived/files > /dev/null 2>&1

cd  NSO_final_project

ssh-keygen -f "/root/.ssh/known_hosts" -R "bastion" > /dev/null 2>&1

ssh-keygen -f "/root/.ssh/known_hosts" -R "haproxy" > /dev/null 2>&1


ansible-playbook app.yml
