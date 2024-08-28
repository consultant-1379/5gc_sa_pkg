#!/bin/bash

if [[ "$#" = "0" ]]; then
    echo "Wrong number of arguments"
    echo "Usage: upload_docker_images_to_workers.sh <one or multiple docker image tarballs>"
    exit 1
fi

worker_ips=$(kubectl get node -o wide | grep worker | awk '{print $6}')

for worker in $worker_ips
do
  echo -n "uploading images to $worker..."
  for image_file in "$@"
  do
    scp -q -o StrictHostKeyChecking=no $image_file $worker:~/
    image=$(basename $image_file)
    ssh -q -o StrictHostKeyChecking=no $worker "sudo docker load -i $image"
    echo "done"
  done
done
