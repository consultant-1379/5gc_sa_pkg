#!/bin/bash

json_outputs=$(kubectl get nodes -o json)
master_names=($(echo $json_outputs| jq -r  '.items[:3] | .[].status.addresses[] | select(.type=="Hostname") | .address'))
master_ips=($(echo $json_outputs | jq -r  '.items[:3] | .[].status.addresses[] | select(.type=="InternalIP") | .address'))

for endpoint in ${master_ips[@]}
do
  echo "INFO: etcd status on $master_names:"
  master_names=("${master_names[@]:1}") #remove first element
  SSH_OPT="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
  ssh $SSH_OPT nodelocal-api.eccd.local sudo /usr/local/bin/etcdctl --cacert=/etc/kubernetes/etcd/master-ca.crt --cert=/etc/kubernetes/etcd/master-client.crt --key=/etc/kubernetes/etcd/master-client.key --endpoints=$endpoint:2379 endpoint status -w table
done
