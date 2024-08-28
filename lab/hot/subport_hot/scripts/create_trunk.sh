#!/bin/bash

if [ $# -ne 1 ]
  then
    echo "Usage: create_trunk.sh <trunk_parent_subnet>"
    exit 1
fi

parent_subnet=$1

parent_subnet_id=$(openstack subnet show $parent_subnet -c id -f value)

port_list=$(openstack port list | grep $parent_subnet_id | awk '{print $2}')

for port in $port_list
do 
  server_id=$(openstack port show $port -c device_id -f value)
  server_name=$(openstack server show $server_id -c name -f value)
  echo openstack network trunk create --parent-port $port ${server_name}_trunk
  openstack network trunk create --parent-port $port ${server_name}_trunk
done
