#!/usr/bin/env bash

set -e -o pipefail

# ==========================
# Revision logs
# ==========================
# - 2021-07-14 eyanpho Add containerd service restart to make self-signed certs effect.
#   Note: From CCD 2.18, containerd is seperated from docker. For self-signed private registry,
#   it needs to restart containerd service when upload self-signed certs to system.
#   Refer to: http://hypernephelist.com/2021/03/23/kubernetes-containerd-certificate.html.
#
# - 2021-07-20 eyanpho Only restart containerd service on worker ndoe and director as there is
#   an issue on master contaniner service restart.
#
# - 2022-01-04 eyanpho add ccd version check for updating self-signed CA will not require
#   containerd restart since 2.20.0


if [[ $# -gt 0 ]]
then
    echo "This script is used to add Team Blues Root CA to all the nodes in the CCD cluster."
    echo "Please run on the director node."
    echo "Example: ./add_ca_to_ccd.sh"
    exit 0
fi

remote_path=/etc/pki/trust/anchors/
cacert_path=../../../../certs/TeamBluesRootCA.crt

echo -e -n "INFO: Upload Team Blues Root CA to node director ${remote_path}...\t"
if [ ! -f /etc/pki/trust/anchors/TeamBluesRootCA.crt ];then
  sudo cp $cacert_path /etc/pki/trust/anchors/
  sudo update-ca-certificates 2>/dev/null
  echo "[OK]"
else
  echo "[Skipped]"
fi

ccd_version=$(cat /etc/eccd/eccd_image_version.ini  | grep IMAGE_RELEASE | awk -F\= '{print $2}')
res=$(python -c $'from packaging import version\nprint(0 if version.parse("2.18.0") <= version.parse("'"$ccd_version"'") < version.parse("2.20.0") else 1);')

nodes=$(kubectl get node -o wide | grep -v NAME | awk '{print $1":"$6}')

for node in ${nodes}
do
    node_name=$(echo $node | awk -F: '{print $1}')
    node_ip=$(echo $node | awk -F: '{print $2}')
    echo -e -n "INFO: Upload Team Blues Root CA to node ${node_name} ${remote_path}...\t"
    if ssh -q -o StrictHostKeyChecking=no ${node_ip} "test -f ${remote_path}/TeamBluesRootCA.crt";then
      echo "[Skipped]"
      continue
    fi
    scp -q -o StrictHostKeyChecking=no $cacert_path ${node_ip}:~/
    ssh -q -o StrictHostKeyChecking=no ${node_ip} "sudo mv ~/TeamBluesRootCA.crt ${remote_path}"
    echo "[OK]"
    if [ $res -eq 0 ];then
      if [[ $node_name =~ ^worker-pool.*$ ]];then
        echo -e -n "INFO: Update ca certificates and Restarting containerd service on ${node_name}...\t"
        ssh -q -o StrictHostKeyChecking=no ${node_ip} "sudo update-ca-certificates 2>/dev/null && sudo systemctl try-reload-or-restart containerd"
        echo "[OK]"
      else
        echo -e -n "INFO: Update ca certificates on ${node_name}...\t"
        ssh -q -o StrictHostKeyChecking=no ${node_ip} "sudo update-ca-certificates 2>/dev/null"
        echo "[OK]"
      fi
    else
      echo -e -n "INFO: Update ca certificates on ${node_name}...\t"
      ssh -q -o StrictHostKeyChecking=no ${node_ip} "sudo update-ca-certificates 2>/dev/null"
      echo "[OK]"
    fi
done
