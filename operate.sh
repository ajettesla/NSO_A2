#!/bin/bash

# Ensure the script receives exactly three arguments
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <openrc_file> <tag> <sshkey>"
    exit 1
fi

# Assign arguments to variables
openrc_file=$1
tag=$2
sshkey=$3

# Source the OpenRC file to set environment variables
source "$openrc_file"

# Path to the configuration file
config_file="server.conf"

# Ensure the configuration file exists
if [ ! -f "$config_file" ]; then
    echo " $(date +%T) Configuration file not found!"
    exit 1
fi

# Signal handlers
trap 'echo " $(date +%T) Ctrl-C pressed. Exiting after sleep."; exit 0' SIGINT
trap 'echo " $(date +%T) Ctrl-X pressed. Exiting immediately."; exit 0' SIGTSTP

while true; do
    # Read the number from the configuration file
    number=$(cat "$config_file")

    # Check if the variable is empty
    if [ -z "$number" ]; then
        echo " $(date +%T) No number found in configuration file!"
        exit 1
    fi

    export image_name='Ubuntu 22.04 Jammy Jellyfish x86_64'
    export flavor_name='m1.small'

    # Print the value to verify
    echo " $(date +%T) Desired number of servers: $number"

    # Get the current number of servers with "dev" in their name
    nofsr=$(openstack server list -f csv | grep "dev" | wc -l)
    echo " $(date +%T) Number of servers running is $nofsr"

    # Reset the trap for Ctrl-C to ensure proper behavior during critical operations
    trap 'echo " $(date +%T) Ctrl-C pressed. Waiting for settings to be applied before exiting."' SIGINT

    # Flag to check if any changes were made
    changes_made=false

    if [ "$number" -lt "$nofsr" ]; then
        # Calculate how many servers need to be deleted
        check=$(($nofsr - $number))

        # List servers with the specific tag
        servers_with_tag=$(openstack server list --tags "${tag}dev" -f csv | grep "dev" | cut -d "," -f1 | tr -d '"' | head -n "$check")

        for server_id in $servers_with_tag; do
            openstack server delete "$server_id"
            if [ $? -eq 0 ]; then
                echo " $(date +%T) Server $server_id ($(openstack server show $server_id -f json | jq -r '.name')) deleted"
                changes_made=true
            else   
                echo "$(date +%T) Failed to delete server $server_id ($(openstack server show $server_id -f json | jq -r '.name')) "
                openstack server show "$server_id"
                openstack server list --tags "${tag}dev" -f csv
                exit 1
            fi
        done

    elif [ "$number" -gt "$nofsr" ]; then
        # Calculate how many more servers need to be created
        check=$(($number - $nofsr))

        for x in $(seq 1 "$check"); do
            openstack server create --os-compute-api-version 2.52 --image "$image_name" --flavor "$flavor_name" --network vrundhavan_private --key-name "$sshkey" --security-group internal_security_group -f json --tag "${tag}dev" dev_"$(($nofsr + $x))" 1>/dev/null
            if [ $? -eq 0 ]; then
                echo " $(date +%T) dev_$(($nofsr + $x)) is created"
                changes_made=true
            else   
                echo " $(date +%T) Failed to create dev_$(($nofsr + $x))"
                exit 1
            fi
        done
    else
        echo " $(date +%T) Number of servers running and required servers are equal ($number)."
    fi

    # Apply changes only if servers were created or deleted
    if [ "$changes_made" = true ]; then
        # Define filenames
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
            addresses=$(echo "$value" | jq -r '.addresses | to_entries[] | .value[0]')
            tags=$(echo "$value" | jq -r '.tags[]' 2>/dev/null || echo "")

            sleep 1
            # Check for 'dev', 'proxy', or 'bastion' tags and write to appropriate section
            if [[ "$tags" == *"dev"* ]]; then
                if [[ -n "$addresses" ]]; then
                    echo "$name ansible_host=$addresses ansible_ssh_private_key_file=${sshkey}.pem" >> "$dev_file"
                else
                    sleep 1
                    address=$(openstack server show "$id" | grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')
                    if [[ -n $address ]]; then
                        echo "$name ansible_host=$address ansible_ssh_private_key_file=${sshkey}.pem" >> "$dev_file"
                    else
                        echo "$(date +%T) Something wrong with the address for $name. Values received: $addresses"
                    fi
                fi
            elif [[ "$tags" == *"proxy"* ]]; then
                if [[ -n "$addresses" ]]; then
                    echo "$name ansible_host=$addresses ansible_ssh_private_key_file=${sshkey}.pem" >> "$proxy_file"
                else
                    echo " $(date +%T) Something wrong with the address for $name. Values received: $addresses"
                fi
            elif [[ "$tags" == *"bastion"* ]]; then
                # Handle case where there may be multiple IP addresses
                addresses=$(echo "$value" | jq -r '.addresses | to_entries[] | .value[1] // empty' | head -n 1)
                if [[ -n "$addresses" ]]; then
                    echo "$name ansible_host=$addresses ansible_ssh_private_key_file=${sshkey}.pem" >> "$bastion_file"
                else
                    echo " $(date +%T) Something wrong with the address for $name. Values received: $addresses"
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

        cp "${sshkey}.pem" NSO_final_project/

        chmod 600 "NSO_final_project/${sshkey}.pem" > /dev/null 2>&1

        rm -rf NSO_final_project/roles/ansible/files/NSO_final_project.zip > /dev/null 2>&1

        zip -r NSO_final_project/roles/ansible/files/NSO_final_project.zip NSO_final_project > /dev/null 2>&1

        cd NSO_final_project

        ansible-playbook app.yml
        
        cd ..
    else
        echo " $(date +%T) No changes were made, skipping inventory update and Ansible playbook execution."
    fi

    # Restore trap for Ctrl-C during sleep
    trap 'echo " $(date +%T) Ctrl-C pressed. Exiting after sleep."; exit 0' SIGINT

    # Sleep for 30 seconds before checking again
    sleep 30
done
