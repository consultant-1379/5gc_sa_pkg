#!/usr/bin/python

import os
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict

Red = '\033[31m'
Green = '\033[32m'
Yellow = '\033[33m'
Blue = '\033[34m'
Magenta = '\033[35m'
Cyan = '\033[36m'
HRed = '\033[41m'
HGreen = '\033[42m'
HYellow = '\033[43m'
ENDC = '\033[0m'
BOLD = '\033[1m'
UNDERLINE = '\033[4m'

def get_cpu_layout(hostname):
    cpu_layout_dict = defaultdict(dict)
    proc_cpuinfo = os.popen("ssh -q {0} cat /proc/cpuinfo | egrep 'processor|core id|physical id'".format(hostname)).read().splitlines()
    physical_id = 0
    core_id = 0
    processor = 0
    for line in proc_cpuinfo:
        if "processor" in line:
            processor = int(line.split(":")[1].strip())
        elif "physical id" in line:
            physical_id = int(line.split(":")[1].strip())
            if physical_id not in cpu_layout_dict.keys():
                cpu_layout_dict[physical_id] = defaultdict(list)
        elif "core id" in line:
            core_id = int(line.split(":")[1].strip())
            cpu_layout_dict[physical_id][core_id].append(processor)
    return cpu_layout_dict

def get_vm_info(hostname):
    domain_list = os.popen("ssh -q {0} 'sudo virsh list' | grep running".format(hostname) + " | awk '{print $2}'").read().splitlines()
    vm_info = defaultdict(dict)
    for domain in domain_list:
        vm_xml = os.popen("ssh -q {0} 'sudo virsh dumpxml {1}'".format(hostname, domain)).read()
        root = ET.fromstring(vm_xml)
        nova_name_tag = root.find(".//{http://openstack.org/xmlns/libvirt/nova/1.0}name")
        if nova_name_tag != None:
            vm_name = nova_name_tag.text
        else:
            vm_name = root.find("./name").text
        vm_info[domain]["name"] = vm_name
        mem_kb = root.find("./memory").text
        mem_gb =  int(mem_kb)/1024/1024
        vm_info[domain]["mem"] = mem_gb
        vcpu_list = []
        for vcpu in root.findall("./cputune/vcpupin"):
            vcpu_list.append(int(vcpu.get('cpuset')))
        vm_info[domain]["cpu"] = vcpu_list
    return vm_info

def get_host_mem(hostname):
    hugepage_info = os.popen('ssh -q {0} "cat /sys/devices/system/node/node*/meminfo | grep -i huge"'.format(hostname)).read().splitlines()
    hugepage_stats = defaultdict(list)
    for line in hugepage_info:
        if "Node 0 HugePages_Total" in line:
            huge_total_0 = int(line.split(":")[1].strip())
            hugepage_stats[0].append(huge_total_0)
        elif "Node 0 HugePages_Free" in line:
            huge_free_0 = int(line.split(":")[1].strip())
            hugepage_stats[0].append(huge_free_0)
        elif "Node 1 HugePages_Total" in line:
            huge_total_1 = int(line.split(":")[1].strip())
            hugepage_stats[1].append(huge_total_1)
        elif "Node 1 HugePages_Free" in line:
            huge_free_1 = int(line.split(":")[1].strip())
            hugepage_stats[1].append(huge_free_1)
    return hugepage_stats

def color_print(hostname):
    color_list = [Red, Green, Yellow, Blue, Magenta, Cyan, HGreen, HRed, HYellow]
    cpu_layout = get_cpu_layout(hostname)
    vm_info = get_vm_info(hostname)
    hugepage_stats = get_host_mem(hostname)
    vm_list = vm_info.keys()
    vm_list.sort()
    print hostname
    print "--------------------------"
    i = 0
    for vm in vm_list:
        print color_list[i] + "{0:16}".format(vm_info[vm]["name"]) + str(len(vm_info[vm]["cpu"])) + "   " + str(vm_info[vm]["mem"]) + "G" + ENDC
        #print color_list[i] + "{0:20}".format(vm_info[vm]["name"]) + str(vm_info[vm]["cpu"]) + "   " + str(vm_info[vm]["mem"]) + "G" + ENDC
        i = i + 1
    print "--------------------------"
    print "HugePages  Total  Free"
    for numa in hugepage_stats.keys():
        print "NUMA {0}:   ".format(numa),
        print "{0:6}".format(str(hugepage_stats[numa][0])),
        print Green + "{0}".format(hugepage_stats[numa][1]) + ENDC
    print "--------------------------"
    print "Core",
    for physical_id in cpu_layout.keys():
        print "   NUMA {0}".format(physical_id),
    print ''
    for core_id in cpu_layout[0].keys():
         print "{0:5}".format(str(core_id)),
         for physical_id in cpu_layout.keys():
             print "[",
             for processor in cpu_layout[physical_id][core_id]:
                 processor_print = "{0:2}".format(str(processor))
                 i = 0
                 for vm in vm_list:
                     if processor in vm_info[vm]["cpu"]:
                         processor_print = color_list[i] + "{0:2}".format(str(processor)) + ENDC
                     i = i + 1
                 print processor_print,
             print "] ",
         print ''
    print ''

def compute_str_compare(x, y):
    if len(x) > len(y):
        return 1
    elif len(x) == len(y):
        if x > y:
            return 1
        elif x == y:
            return 0
        else:
            return -1
    else:
        return -1

def usage():
    print "Usage: check_vnf_cpupin.py all|compute-0-x"

if __name__ == "__main__":

    try:
        opt = sys.argv[1]
    except IndexError:
        usage()
        sys.exit(1)

    get_host_mem(opt)
    color_print(opt)

'''
    compute_host_list = os.popen("fuel node list | grep compute | awk '{print $5}'").read().splitlines()
    if opt == "all":
        compute_host_list.sort(cmp=compute_str_compare)
    elif opt != "all" and opt in compute_host_list:
        compute_host_list = [opt]
    else:
        usage()
        sys.exit(1)

    for compute_host in compute_host_list:
        color_print(compute_host)
'''

