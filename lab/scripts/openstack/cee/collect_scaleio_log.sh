#!/bin/bash

## collect scaleio VxSDS storage log
trap "cleanup" EXIT

function cleanup()
{
  rm -rf ${OUTPUT_DIRS[@]}
  for n in ${scaleio_computes[@]}
  do
    ssh -q -i /home/ceeadm/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${n} "\
        trap \"sudo rm -rf $TMPDIR\" EXIT" 
  done
}

# only genearte a TEMPDIR name, all data will be stored in this directory on scaleio computes
TMPDIR=$(mktemp -u -t "scaleio.XXXXXXXX")
OUTPUT_DIRS=()
if [ $# -ge 6 ];then
  pod=$1
  shift
  scaleio_computes=$@
  for n in ${scaleio_computes[@]}
  do
    OUTPUT_DIRS+=(${n}_scaleio)
    {
      ssh -q -i /home/ceeadm/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${n} "\
        sudo mkdir -p $TMPDIR; \
        sudo cp -a /opt/emc/scaleio $TMPDIR/scaleio; \
        sudo /opt/emc/scaleio/mdm/diag/get_info.sh -u cinder -p Sysadmin123 -d $TMPDIR/get_info; \
    	  sudo cp -a /var/log/scaleio $TMPDIR/log; \
  	    sudo chmod -R 775 $TMPDIR"
      scp -q -i /home/ceeadm/.ssh/id_rsa -r ${n}:$TMPDIR ${n}_scaleio
    } &
  done
  wait
  tgz_file_name=$pod-scaleio-$(date "+%Y-%m-%d-%H-%M-%S").tgz
  tar zcvf $tgz_file_name ${OUTPUT_DIRS[@]}
fi
