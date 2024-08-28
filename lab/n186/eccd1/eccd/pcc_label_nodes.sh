#!/bin/bash

## Add PCC Label for std worker nodes for Dual-Mode 5GC on CNIS

std_worker_count=$(kubectl get node --selector='!type'  | grep -v ^NAME | wc -l)
[ $std_worker_count -lt 3 ] && echo Error: insufficient STD worker node count

nodes_seq=($(seq 0 $(($std_worker_count-1))))
mm_ctrl_list=$(echo ${nodes_seq[@]:0:3} | tr ' ' ',') # first two
mm_non_ctrl_list=$(echo ${nodes_seq[@]:3} | tr ' ' ',') # from third to end
sm_ctrl_list=$(echo ${nodes_seq[@]:(-1,-2)} | tr ' ' ',') # last two nodes
sm_non_ctrl_list=$(echo ${nodes_seq[@]:0:${#nodes_seq[@]}-2} | tr ' ' ',') # from first to the third from last one

kubectl label node $(kubectl get nodes --selector='!type' -o json | jq -r .items[$mm_ctrl_list].metadata.name) pcc-mm-pod=controller
kubectl label node $(kubectl get nodes --selector='!type' -o json | jq -r .items[$mm_non_ctrl_list].metadata.name) pcc-mm-pod=non-controller
kubectl label node $(kubectl get nodes --selector='!type' -o json | jq -r .items[$sm_ctrl_list].metadata.name) pcc-sm-pod=controller
kubectl label node $(kubectl get nodes --selector='!type' -o json | jq -r .items[$sm_non_ctrl_list].metadata.name) pcc-sm-pod=non-controller
