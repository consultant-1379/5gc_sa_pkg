#!/bin/bash
# set -x

if [[ "$#" != "4" ]]; then
    echo "Wrong number of arguments"
    echo "Usage: test_trunk.sh <interface> <vlan> <ip> <gw>"
    echo "Example: test_trunk.sh eth1 3854 11.1.54.20/24 11.1.54.254"
    exit 1
fi

intf=$1
vid=$2
ip=$3
gw=$4
ip link add link ${intf} name vlan${vid} type vlan id ${vid}
ip a a ${ip} dev vlan${vid}
ip link set dev vlan${vid} up
ping ${gw} -c 1
ip link delete dev vlan${vid}
