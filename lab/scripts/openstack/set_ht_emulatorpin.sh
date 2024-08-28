#!/usr/bin/env bash

help()
{
    echo "Usage: $0 -g <HT host aggregate> [ -c <target vCPU for emulatorpin> ]"
    echo "Examples:"
    echo "  Check current emulatorpin thread: $0 -g HT"
    echo "  Set emulatorpin thread to vCPU 1: $0 -g HT -c 1"
    exit 1
}

while getopts 'g:c:h' OPT; do
    case $OPT in
        g) aggregate="$OPTARG";;
        c) new_vcpu="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done

if [[ -z ${aggregate} ]]; then
    echo "Error: missing host aggregate argument"
    help
fi

ht_hosts=$(openstack aggregate show ${aggregate} -f json | jq -r .hosts[] | xargs)
echo "Found computes in host aggregate ${aggregate}: ${ht_hosts}"
echo

for host in ${ht_hosts}
do
    instance_list=$(ssh -q ${host} sudo virsh list | grep instance | awk '{print $2}' | xargs)
    echo "Login ${host}, found instances: ${instance_list}"
    for instance in ${instance_list}
    do
        echo "Checking VM instance: ${instance}"
        vm=$(ssh -q ${host} sudo virsh dumpxml ${instance} | grep nova:name | cut -d'>' -f2 | cut -d'<' -f1)
        echo "  VM name: ${vm}"
        old_pcpu=$(ssh -q ${host} sudo virsh emulatorpin ${instance} | grep \* | cut -d: -f2 | cut -d, -f1 | cut -d- -f1)
        echo "  Current physical CPU for emulatorpin thread: ${old_pcpu}"
        old_vcpu=$(ssh -q ${host} sudo virsh vcpupin ${instance} | grep :${old_pcpu}$ | cut -d: -f1)
        echo "  Current vCPU for emulatorpin thread: ${old_vcpu}"
        if [[ -n ${new_vcpu} ]]; then
            echo "  New vCPU for emulatorpin thread: ${new_vcpu}"
            new_pcpu=$(ssh -q ${host} sudo virsh vcpupin ${instance} | grep "^\s*${new_vcpu}:" | cut -d: -f2)
            echo "  New physical CPU for emulatorpin thread: ${new_pcpu}"
            echo -n "Setting emulatorpin thread..."
            ssh -q ${host} sudo virsh emulatorpin ${instance} ${new_pcpu} --live && echo "Done" || echo "Failed"
            #echo "ssh -q ${host} sudo virsh emulatorpin ${instance} ${new_pcpu} --live"
        fi
        echo
    done
done
