#!/usr/bin/python

import os
import sys
import re
import json

username = 'ceeadm'
hostname = sys.argv[1]

SSH_OPTIONS = "-q -o StrictHostKeyChecking=no"


neutron_port_list = os.popen("neutron port-list -c name -c binding:vif_details -f json -q 2>/dev/null").read()

dpctl_show = os.popen("ssh {0} {1}@{2} 'sudo ovs-appctl dpctl/show | grep -v tap'".format(SSH_OPTIONS, username, hostname)).read().splitlines()

pmd_rxq_show = os.popen("ssh {0} {1}@{2} 'sudo ovs-appctl dpif-netdev/pmd-rxq-show'".format(SSH_OPTIONS, username, hostname)).read().splitlines()

neutron_port_dict_list = json.loads(neutron_port_list)

ovs_port_all = {}

for port in neutron_port_dict_list:
    if port["binding:vif_details"].has_key("vhostuser_socket"):
        ovs_port_name = port["binding:vif_details"]["vhostuser_socket"].split("/")[4]
        ovs_port_info = {}
        ovs_port_info["neutron_port"] = port["name"]
        ovs_port_all[ovs_port_name] = ovs_port_info


for line in dpctl_show:
    line = line.replace('\t', ' ')
    m = re.match("\s+port (\d+)\: (\S+)", line)
    if m != None:
        port_num = m.group(1)
        ovs_port_name = m.group(2)
        if 'dpdk' in ovs_port_name:
            ovs_port_info = {}
            ovs_port_info["port_num"] = port_num
            ovs_port_info["neutron_port"] = 'NULL'
            ovs_port_all[ovs_port_name] = ovs_port_info

        elif ovs_port_name in ovs_port_all.keys():
            ovs_port_all[ovs_port_name]["port_num"] = port_num

for line in pmd_rxq_show:
    line = line.replace('\t', ' ')
    if 'pmd thread' in line:
        m = re.match("pmd thread numa_id (\d+) core_id (\d+):", line)
        numa_id = m.group(1)
        cpu_id = m.group(2)
    elif 'port' in line:
        m = re.match("\s+port:\s+(\S+)\s+queue-id:\s+(\d+)", line)
        #m = re.match("\s+port:\s+(\S+)\s+queue-id:\s+(\d+)\s+pmd\s+usage:\s+(\d+)\s+%", line)
        if m:
            ovs_port_name = m.group(1)
            port_q = m.group(2)
            #pmd_usage = m.group(3)
            if ovs_port_name in ovs_port_all.keys():
                ovs_port_all[ovs_port_name]["pmd_cpu"] = "{0}.{1}".format(numa_id, cpu_id)
                #ovs_port_all[ovs_port_name]["pmd_usage"] = "{0}%".format(pmd_usage)

print "-------------------------------------------------------"
print "OVS_Port         ID  PMD_CPU     Neutron_Port"
print "-------------------------------------------------------"

ovs_port_list = ovs_port_all.keys()
ovs_port_list.sort()

for ovs_port_name in ovs_port_list:
    if ovs_port_all[ovs_port_name].has_key("port_num"):
        #print ovs_port_all[ovs_port_name]
        #continue
        print "{0:17}{1:4}{2:12}{3:30}".format(ovs_port_name, ovs_port_all[ovs_port_name]["port_num"], ovs_port_all[ovs_port_name]["pmd_cpu"], ovs_port_all[ovs_port_name]["neutron_port"])
print "-------------------------------------------------------"

#print ovs_port_all, "\n"


#print neutron_port_list_dict
#print dpctl_show
#print pmd_rxq_show

