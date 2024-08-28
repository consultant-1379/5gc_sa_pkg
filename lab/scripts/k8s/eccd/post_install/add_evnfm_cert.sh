#!/usr/bin/env bash
set -e

if [[ $# -lt 1 ]]; then
    echo "Error: Wrong number of arguments"
    echo "Usage: add_evnfm_cert.sh <evnfm_registry> <registry_cert_file>"
    echo "Example: ./add_evnfm_cert.sh evnfm-docker-registry.ingress.n84-eccd2.sero.gic.ericsson.se"
    echo "         ./add_evnfm_cert.sh evnfm-docker-registry.ingress.n28-eccd2.sero.gic.ericsson.se"
    echo "         ./add_evnfm_cert.sh evnfm-docker-registry.ingress.n99-eccd2.sero.gic.ericsson.se"
    exit 1
fi


ccd_version=$(cat /etc/eccd/eccd_image_version.ini  | grep IMAGE_RELEASE | awk -F\= '{print $2}')
res=$(python -c $'from packaging import version\nprint(0 if version.parse("'"$ccd_version"'") >= version.parse("2.20.0") else 1);')
cacert=../../../../certs/TeamBluesRootCA.crt

for evnfm_registry in $@
do
  worker_ips=$(kubectl get node -o wide | grep worker | awk '{print $1":"$6}')
  for worker in ${worker_ips}
  do
      wname=$(echo $worker | awk -F: '{print $1}')
      wip=$(echo $worker | awk -F: '{print $2}')
      echo -e -n "Add EVNFM registry $evnfm_registry CA cert on worker ${wname}...\t"
      scp -q -o StrictHostKeyChecking=no $cacert ${wip}:~/ca.crt
      if [ $res -eq 0 ];then
        ssh -q -o StrictHostKeyChecking=no ${wip} "sudo mkdir -p /etc/docker/certs.d/${evnfm_registry} /etc/containerd/certs.d/${evnfm_registry};\
          sudo cp ca.crt /etc/docker/certs.d/${evnfm_registry};\
          sudo cp ca.crt /etc/containerd/certs.d/${evnfm_registry};\
          sudo rm -rf ~/ca.crt"
        echo "[OK]"
      else
        ssh -q -o StrictHostKeyChecking=no ${wip} "sudo mkdir -p /etc/docker/certs.d/${evnfm_registry};\
          sudo cp ca.crt /etc/docker/certs.d/${evnfm_registry};\
          sudo rm -rf ~/ca.crt"
        echo "[OK]"
      fi
  done
done
