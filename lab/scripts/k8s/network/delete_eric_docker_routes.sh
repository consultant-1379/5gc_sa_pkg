#!/bin/bash
worker_ips=$(kubectl get node -o wide | grep worker | awk '{print $6}')

for worker in $worker_ips
do
  echo "Delete static routes on $worker..."
  ssh -q $worker "sudo ip route delete 10.210.99.0/24" 
  ssh -q $worker "sudo ip route delete 10.117.107.0/24"
done
