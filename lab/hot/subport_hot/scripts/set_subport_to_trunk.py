#!/usr/bin/python

import os
import sys
import json

try:
    stack_name = sys.argv[1]
except IndexError:
    print("Usage: set_subport_to_trunk.py <subport stack name>")
    sys.exit(1)

TRUNKSET = "openstack network trunk set --subport port=" \
           "{trunk_name}_{net_name}_{vlan_id}_subport," \
           "segmentation-type=vlan," \
           "segmentation-id={vlan_id} " \
           "{trunk_name}"

STACKENV = "openstack stack environment show {0} -f json"

stack_env = os.popen(STACKENV.format(stack_name)).read()

stack_env_json = json.loads(stack_env)

for pool in stack_env_json["parameters"]["networks_on_trunks"]:
    for network in pool["networks"]:
        for trunk in pool["trunks"]:
            print(TRUNKSET.format(trunk_name=trunk["trunk"],
                                  net_name=network["network"], 
                                  vlan_id=network["vlan"]))
            os.popen(TRUNKSET.format(trunk_name=trunk["trunk"], 
                                     net_name=network["network"], 
                                     vlan_id=network["vlan"]))

