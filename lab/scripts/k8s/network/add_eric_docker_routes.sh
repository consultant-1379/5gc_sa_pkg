#!/bin/bash
worker_ips=$(kubectl get node -o wide | grep worker | awk '{print $6}')

for worker in $worker_ips
do
  echo "Add static routes on $worker..."
  ssh -q $worker "sudo ip route add 10.210.99.0/24 via 10.0.10.1" 
  ssh -q $worker "sudo ip route add 10.117.107.0/24 via 10.0.10.1"
done
