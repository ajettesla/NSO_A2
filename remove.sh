openrc_file=$1
tag=$2
sshkey=$3

source $openrc_file

openstack keypair delete ${sshkey} 2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo " $(date +%T ) keypair is removed "
else
    echo " $(date +%T ) Failed to remove keypair"
fi

for x in $(openstack floating ip list -f json | jq -r '.[]."Floating IP Address"'); do  
    if [[ "$(openstack floating ip show $x -f json | jq -r '.tags')" == *"${tag}"* ]]; then   
            openstack floating ip delete $x
            echo " $(date +%T) $x id deleted"; 
    else     
            echo " $(date +%T) Failed to delete floating ip $x" ; 
    fi; 
done

for server_id in $(openstack server list -f json | jq -r '.[].ID'); do
    if [[ "$(openstack server show $server_id -f json | jq -r '.tags[]' 2>/dev/null)" == *"${tag}"* ]]; then
        openstack server delete $server_id
        if [ $? -eq 0 ]; then
            echo " $(date +%T) $server_id ($(openstack server show $server_id -f json | jq -r '.name')) is deleted "
        else
            echo " $(date +%T) Failed to delete server $server_id ($(openstack server show $server_id -f json | jq -r '.name'))"
        fi
    else
        echo " $(date +%T) Server $server_id does not have the 'ajet' tag"
    fi
done


openstack router remove subnet router_1 private_subnet  > /dev/null  2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) private subnet is removed  from router 1 " 
else 
    echo " $(date +%T ) Failed to remove private subnet from router_1"
fi

openstack router remove subnet router_1 public_subnet  > /dev/null 2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) public sunet is removed form router 1 " 
else 
    echo " $(date +%T ) Failed to remove public subnet from router 1"
fi

openstack router unset --external-gateway router_1  > /dev/null  2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) router unset external gateway" 
else 
    echo " $(date +%T ) Failed to unset external gateway"
fi

openstack subnet delete private_subnet > /dev/null 2>&1 

if [ $? = 0 ]; then
    echo " $(date +%T ) private subnet is removed " 
else 
    echo " $(date +%T ) Failed to remove private subnet"
fi

openstack subnet delete public_subnet  > /dev/null 2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) public subnet is removed " 
else 
    echo " $(date +%T ) Failed to remove public subnet"
fi

openstack router delete router_1 > /dev/null 2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) router_1 is removed " 
else 
    echo " $(date +%T ) Failed to remove router_1"
fi

openstack network delete vrundhavan_public > /dev/null  2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) public network is removed " 
else 
    echo " $(date +%T ) Failed to remove public network"
fi

openstack network delete vrundhavan_private  > /dev/null 2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) private network is removed " 
else 
    echo " $(date +%T ) Failed to remove private network"
fi

openstack security group delete internal_security_group  > /dev/null 2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) internal sc is removed " 
else 
    echo " $(date +%T ) Failed to remove internal sc"
fi

openstack security group delete external_security_group  > /dev/null 2>&1

if [ $? = 0 ]; then
    echo " $(date +%T ) sg external is removed " 
else 
    echo " $(date +%T ) Failed to remove sc external"
fi

rm -rf ${sshkey}.pem

rm -rf openstack_inventory

rm -rf NSO_final_project/


