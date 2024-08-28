#!/usr/bin/env bash

CEE_CMD_LIST=(
"cat /etc/cee_version.txt"
"openstack compute service list"
"openstack hypervisor list --long"
"openstack availability zone list --long"
"openstack server list --long"
"openstack flavor list --long"
"openstack volume list --long"
)

CEE_NW_CMD_LIST=(
"openstack network list --long"
"openstack subnet list --long"
"openstack network trunk list"
"openstack port list --long"
"neutron l2-gateway-list"
"neutron l2-gateway-connection-list"
)

SSH_OPTIONS="-q -o StrictHostKeyChecking=no"

usage()
{
    echo
    echo "Collects CEE/OpenStack logs."
    echo "Script needs to be run in CIC."
    echo
    echo "Usage: $(tput bold)${0} LOG-NAME $(tput sgr0)"
    echo
    exit 1
}

get_common_logs()
{
    local log_directory=$1
    local dir="${log_directory}"/common
    mkdir -p "${dir}"

    for cmd in "${CEE_CMD_LIST[@]}"; do
        
        echo "$(date "+%H:%M:%S"): Getting data: ${cmd}" | tee -a "${summary_log}"

        local log
        log=$(echo "${cmd}" | awk '{system($0)}' | tr -d '\0')

        local filename
        filename=$(gen_filename "${cmd}")
        echo "${log}" > "${dir}/${filename}"
    done
    echo "---------------------------------------------" | tee -a "${summary_log}"
}

get_network_logs()
{
    local log_directory=$1
    local dir="${log_directory}"/network
    mkdir -p "${dir}"

    for cmd in "${CEE_NW_CMD_LIST[@]}"; do

        echo "$(date "+%H:%M:%S"): Getting data: ${cmd}" | tee -a "${summary_log}"

        local log
        log=$(echo "${cmd}" | awk '{system($0)}' | tr -d '\0')

        local filename
        filename=$(gen_filename "${cmd}")
        echo "${log}" > "${dir}/${filename}"
    done

    for network in $(openstack network list -c "Name" -f value); do
        echo "$(date "+%H:%M:%S"): Getting ${network} detail" | tee -a "${summary_log}"
        echo "------------- Network: ${network} ---------------" >> "${dir}/network-detail.yaml"
        openstack network show ${network} -f yaml >> "${dir}/network-detail.yaml"
        echo "-------------------------------------------------" >> "${dir}/network-detail.yaml"
    done

    for trunk in $(openstack network trunk list -c "Name" -f value); do
        echo "$(date "+%H:%M:%S"): Getting ${trunk} detail" | tee -a "${summary_log}"
        echo "------------- Trunk: ${trunk} ---------------" >> "${dir}/trunk-detail.yaml"
        openstack network trunk show ${trunk} -f yaml >> "${dir}/trunk-detail.yaml"
        echo "-------------------------------------------------" >> "${dir}/trunk-detail.yaml"
    done

    echo "---------------------------------------------" | tee -a "${summary_log}"
}


get_stack_logs()
{
    local log_directory=$1
    local dir="${log_directory}"/stack
    mkdir -p "${dir}"

    echo "$(date "+%H:%M:%S"): Getting stack info" | tee -a "${summary_log}"
    openstack stack list >> "${dir}/stack-list.log"

    for stack in $(openstack stack list -c "Stack Name" -f value); do
        echo "$(date "+%H:%M:%S"): Getting ${stack} environment and events" | tee -a "${summary_log}"
        openstack stack environment show ${stack} >> "${dir}/env-output-${stack}.yaml"
        openstack stack event list ${stack} --nested-depth 5 >> "${dir}/${stack}-event-list.log"
    done

    echo "---------------------------------------------" | tee -a "${summary_log}"
}

get_ovs_logs()
{
    local log_directory=$1
    local dir="${log_directory}"/ovs
    mkdir -p "${dir}"

    echo "$(date "+%H:%M:%S"): Getting OVS log" | tee -a "${summary_log}"

    for compute in $(openstack compute service list -c Host -c State --service nova-compute | grep up  | awk '{print $2}' | sort); do
        echo "$(date "+%H:%M:%S"): Getting OVS log from ${compute}" | tee -a "${summary_log}"
        ssh ${SSH_OPTIONS} ${compute} 'sudo chmod a+r ~/port_stats/*'
        port_stats_logs=$(ssh ${SSH_OPTIONS} ${compute} ls ~/port_stats -1rt | grep port_stats.*log | tail -7)
        port_info_logs=$(ssh ${SSH_OPTIONS} ${compute} ls ~/port_stats -1rt | grep port_info | tail -1)
        for file in ${port_stats_logs}; do
            scp ${SSH_OPTIONS} ${compute}:~/port_stats/${file} ${dir}/
        done
        for file in ${port_info_logs}; do
            scp ${SSH_OPTIONS} ${compute}:~/port_stats/${file} ${dir}/
        done
    done

    echo "---------------------------------------------" | tee -a "${summary_log}"

}

gen_filename()
{
    local cmd=$1
    cmd=${cmd//[^a-zA-Z0-9]/-}
    cmd=${cmd//--/-}
    cmd=${cmd:0:250}
    echo "${cmd}.log"
}


#=============================================
# Main
#=============================================

if [[ "$#" != "1" ]]; then
    usage;
fi

log_name=$1

date=$(date +%G%m%d-%H%M%S)
log_directory=${log_name}-${date}-logs
mkdir -p "${log_directory}"
summary_log="${log_directory}/${log_name}-summary.log"



echo "=============================================" | tee "${summary_log}"
echo "Collecting CEE logs" | tee -a "${summary_log}"

get_common_logs ${log_directory}
get_network_logs ${log_directory}
#get_stack_logs ${log_directory}
#get_ovs_logs ${log_directory}

echo "=============================================" | tee -a "${summary_log}"
echo "Log collection is finished"                    | tee -a "${summary_log}"




