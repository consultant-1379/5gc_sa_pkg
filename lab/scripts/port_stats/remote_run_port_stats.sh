#!/usr/bin/env bash

ssh_options="-q -o StrictHostKeyChecking=no"

compute_list=$(openstack compute service list -c Host -c State --service nova-compute | grep up  | awk '{print $2}' | sort)

for compute in ${compute_list}
do
    echo -n "Running port_stats.py on ${compute} ... "
    port_info=$(mktemp)
    ./get_port_cee9.py ${compute} > ${port_info}
    port_list=$(cat ${port_info} | egrep "dpdk|vhu" | awk '{print $2}' | xargs)
    ssh ${ssh_options} ${compute} mkdir -p ~/port_stats
    scp ${ssh_options} port_stats.py ${compute}:~/port_stats/
    scp ${ssh_options} ${port_info} ${compute}:~/port_stats/${compute}-$(date +%m%H%M)-port_info.log
    ssh ${ssh_options} ${compute} "screen -d -m sudo ~/port_stats/port_stats.py ${port_list}"
    echo "done"
    rm ${port_info}
done
