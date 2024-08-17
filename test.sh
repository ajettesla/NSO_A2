process_servers_json() {
    # Define temporary files
    dev_file="dev_inventory.tmp"
    dev_test_file="dev_inventory2.tmp"
    proxy_file="proxy_inventory.tmp"
    proxy_test_file="proxy_inventory2.tmp"
    bastion_file="bastion_inventory.tmp"
    bastion_test_file="bastion_inventory2.tmp"
    inventory_file="openstack_inventory"
    inventory_file2="openstack_inventory2"
    sshc_bastion="sshc_bastion.tmp"

    # Clear the content of the output files before writing
    > "$dev_file"
    > "$dev_test_file"
    > "$proxy_file"
    > "$proxy_test_file"
    > "$bastion_file"
    > "$bastion_test_file"
    > "$sshc_bastion"
    > "$inventory_file"
    > "$inventory_file2"

    # Fetch the JSON output from OpenStack
    #!/bin/bash

servers_json=$(openstack server list -f json --long)

# Check if all servers are active
start_time=$(date +%s)
all_active=true

# Using a while loop with process substitution to avoid subshell
while IFS= read -r server; do
    name=$(echo "$server" | jq -r '.Name')
    power_state=$(echo "$server" | jq -r '."Power State"')

    if [[ "$power_state" != "1" ]]; then 
        all_active=false
        echo  " $date +%T$name is shutdown"
        break
    fi
done < <(echo "$servers_json" | jq -c '.[]')


if [ "$all_active" = false ]; then
    echo  " $date +%TSome servers are not in ACTIVE state. Waiting for up to 60 seconds for them to become active..."

    while : ; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ "$elapsed_time" -ge 60 ]; then
            echo  " $date +%TWaited 60 seconds. Some servers are still not active:"
            echo "$servers_json" | jq -c '.[]' | while IFS= read -r server; do
                name=$(echo "$server" | jq -r '.Name')
                power_state=$(echo "$server" | jq -r '."Power State"')

                if [[ "$power_state" != "1" ]]; then 
                    echo  " $date +%T$name is in SHUTDOWN STATE"
                fi
            done
            break
        fi

        # Re-check the status of all servers
        all_active=true
        servers_json=$(openstack server list -f json --long)
        while IFS= read -r server; do
            name=$(echo "$server" | jq -r '.Name')
            power_state=$(echo "$server" | jq -r '."Power State"')

            if [[ "$power_state" != "1" ]]; then 
                all_active=false
                break
            fi
        done < <(echo "$servers_json" | jq -c '.[]')

        if [ "$all_active" = true ]; then
            echo  " $date +%TAll servers are now in ACTIVE state."
            break
        fi

        sleep 5  # wait before re-checking
    done
else
    echo  " $date +%TAll servers are already in ACTIVE state. Proceeding with the script..."
fi


    # Now continue with the rest of the script (processing servers for inventory creation)
    echo "$servers_json" | jq -c '.[]' | while IFS= read -r server; do
        name=$(echo "$server" | jq -r '.Name')
        power_state=$(echo "$server" | jq -r '."Power State"')
        networks=$(echo "$server" | jq -r '.Networks | to_entries[].value[]')

        # Extract public IP
        public_IP=$(echo "$networks" | grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')

        if [ -n "$public_IP" ]; then
            echo -e "Host $name \n\t Hostname $public_IP \n\t User ubuntu \n\t IdentityFile ~/.ssh/$sshkey" >> $sshc_bastion
            if [[ "$name" == *"dev"* && "$name" == *"$tag"* ]]; then
                echo "$name ansible_host=$public_IP ansible_ssh_private_key_file=~/.ssh/${sshkey}" >> "$dev_file"
                echo "$name" >> $bastion_test_file
            elif [[ "$name" == *"proxy"* && "$name" == *"$tag"* ]]; then
                echo "$name ansible_host=$public_IP ansible_ssh_private_key_file=~/.ssh/${sshkey}" >> "$proxy_file"
                echo "$name" >> $bastion_test_file
            elif [[ "$name" == *"bastion"* && "$name" == *"$tag"* ]]; then
                echo "$name ansible_host=$public_IP ansible_ssh_private_key_file=~/.ssh/${sshkey}" >> "$bastion_file"
                echo "$name" >> $bastion_test_file
            fi
        else 
            echo "$(date +%T) Something went wrong with getting the IP address for $name."
        fi
    done

    # Create the first inventory file
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

    # Create the second inventory file
    {
      echo "[local]"
      echo "localhost ansible_connection=local"
      echo "[dev]"
      cat "$dev_test_file"
      echo "[proxy]"
      cat "$proxy_test_file"
      echo "[bastion]"
      cat "$bastion_test_file"
    } > "$inventory_file2"

    # Clean up temporary files
    rm -f "$dev_file" "$proxy_file" "$bastion_file" "$dev_test_file" "$proxy_test_file" "$bastion_test_file"

    # Append groupings
    {
        echo -e "\n"
        echo "[all:children]"
        echo -e "\n"
        echo "proxy"
        echo "dev"
        echo "bastion"
    } >> "$inventory_file"

    {
        echo -e "\n"
        echo "[all:children]"
        echo -e "\n"
        echo "proxy"
        echo "dev"
        echo "bastion"
    } >> "$inventory_file2"
}

process_servers_csv() {
    # Define temporary files
    dev_file="dev_inventory.tmp"
    dev_test_file="dev_inventory2.tmp"
    proxy_file="proxy_inventory.tmp"
    proxy_test_file="proxy_inventory2.tmp"
    bastion_file="bastion_inventory.tmp"
    bastion_test_file="bastion_inventory2.tmp"
    inventory_file="openstack_inventory"
    inventory_file2="openstack_inventory2"
    sshc_bastion="sshc_bastion.tmp"

    # Clear the content of the output files before writing
    > "$dev_file"
    > "$dev_test_file"
    > "$proxy_file"
    > "$proxy_test_file"
    > "$bastion_file"
    > "$bastion_test_file"
    > "$sshc_bastion"
    > "$inventory_file"
    > "$inventory_file2"

    servers_csv=$(openstack server list -f csv --long | tail -n +2)

    # Check if all servers are active
    start_time=$(date +%s)
    all_active=true

    # Process each server in a loop without creating a subshell
    while IFS=, read -r server; do
        name=$(echo $server | cut -d "," -f 2 | tr -d '"')
        power_state=$(echo $server | cut -d "," -f 5 | tr -d '"')


        if [[ "$power_state" -ne 1 ]]; then 
            all_active=false
            break
        fi
    done < <(echo "$servers_csv")

 

    if [ "$all_active" = false ]; then
        echo  " $date +%TSome servers are not in ACTIVE state. Waiting for up to 60 seconds for them to become active..."
        
        while : ; do
            current_time=$(date +%s)
            elapsed_time=$((current_time - start_time))

            if [ "$elapsed_time" -ge 60 ]; then
                echo  " $date +%TWaited 60 seconds. Some servers are still not active:"
                openstack server list -f csv --long | tail -n +2 | while IFS=, read -r server; do
                    name=$(echo $server | cut -d "," -f 2 | tr -d '"')
                    power_state=$(echo $server | cut -d "," -f 5 | tr -d '"')

                    if [[ "$power_state" -ne 1 ]]; then 
                        echo  " $date +%T$name is in SHUTDOWN STATE"
                    fi
                done
                break
            fi

            # Re-check the status of all servers
            all_active=true
            while IFS=, read -r server; do
                name=$(echo $server | cut -d "," -f 2 | tr -d '"')
                power_state=$(echo $server | cut -d "," -f 5 | tr -d '"')

                if [[ "$power_state" -ne 1 ]]; then 
                    all_active=false
                    break
                fi
            done < <(openstack server list -f csv --long | tail -n +2)

            if [ "$all_active" = true ]; then
                echo  " $date +%TAll servers are now in ACTIVE state."
                break
            fi

            sleep 5  # wait before re-checking
        done
    else
        echo  " $date +%TAll servers are already in ACTIVE state. Proceeding with the script..."
    fi

    # Now continue with the rest of the script (processing servers for inventory creation)
    echo "$servers_csv" | while IFS=, read -r server; do
        name=$(echo $server | cut -d "," -f 2 | tr -d '"')
        power_state=$(echo $server | cut -d "," -f 5 | tr -d '"')
        networks=$(echo $server | cut -d "," -f 6)

        # Extract public IP
        public_IP=$(echo $server | cut -d"," -f 7 | grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')
        private_IP=$(echo $server | cut -d "," -f 6 | grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b')

        if [ -n "$private_IP" ]; then
            echo -e "Host $name \n\t Hostname $private_IP \n\t User ubuntu \n\t IdentityFile ~/.ssh/$sshkey" >> $sshc_bastion
            if [[ "$name" == *"dev"* && "$name" == *"$tag"* ]]; then
                echo "$name ansible_host=$private_IP ansible_ssh_private_key_file=~/.ssh/${sshkey}" >> "$dev_file"
                echo "$name" >> $bastion_test_file
            elif [[ "$name" == *"proxy"* && "$name" == *"$tag"* ]]; then
                echo "$name ansible_host=$private_IP ansible_ssh_private_key_file=~/.ssh/${sshkey}" >> "$proxy_file"
                echo "$name" >> $bastion_test_file
            elif [[ "$name" == *"bastion"* && "$name" == *"$tag"* ]]; then
                echo "$name ansible_host=$public_IP ansible_ssh_private_key_file=~/.ssh/${sshkey}" >> "$bastion_file"
                echo "$name" >> $bastion_test_file
            fi
        else 
            echo "$(date +%T) Something went wrong with getting the IP address for $name."
        fi
    done

    # Create the first inventory file
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

    # Create the second inventory file
    {
      echo "[local]"
      echo "localhost ansible_connection=local"
      echo "[dev]"
      cat "$dev_test_file"
      echo "[proxy]"
      cat "$proxy_test_file"
      echo "[bastion]"
      cat "$bastion_test_file"
    } > "$inventory_file2"

    # Clean up temporary files
    rm -f "$dev_file" "$proxy_file" "$bastion_file" "$dev_test_file" "$proxy_test_file" "$bastion_test_file"
}
