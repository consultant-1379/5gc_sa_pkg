#!/usr/bin/env bash

SSH_OPTIONS="-q -o StrictHostKeyChecking=no"

pvc_info=$(mktemp)
kubectl get pvc --all-namespaces >> $pvc_info

df_info=$(mktemp)
for node in $(kubectl get nodes -o json | jq .items[].status.addresses[0].address | cut -d\" -f2)
do
   ssh ${SSH_OPTIONS} $node 'sudo df -h' >> $df_info
done

echo "Namespace PVC Volume Size Used Avail Use%"

for pv in $(kubectl get pv | grep -v NAME | grep -v eric-pc-storage | awk '{print $1}')
do
  echo -n $(grep $pv $pvc_info | awk '{print $1,$2,$4}')
  echo -n ' '
  grep $pv $df_info | awk '{print $2,$3,$4,$5}'
done

rm $df_info
rm $pvc_info

