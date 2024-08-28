#!/bin/bash

set -euo pipefail

BASEDIR=$(dirname $(readlink -e $0))

SP_ROOTDIR=$BASEDIR/..

function gen_ccd_config()
{
  local CWD=`pwd`
  ADDARG=$@
  SP_ROOTDIR=$HOME/tmp/5gc_sa_pkg

  T1=(n280:n280-eccd1 n280:n280-eccd2 n280:n280-eccd3 n99:n99-eccd1)

  cd $SP_ROOTDIR

  if git pull --rebase >/dev/null 2>&1;then
    echo "Rebase '5gc_sa_pkg'repo successfully."
  else
    echo "Error: failed to rebase '5gc_sa_pkg'"
    exit 1
  fi

  for cluster in ${T1[@]}
  do
    pod=$(echo $cluster | awk -F: '{print $1}')
    cluster_id=$(echo $cluster | awk -F: '{print $2}')
    ceat gen_ccdadm_config -c ${SP_ROOTDIR}/lab/${pod}/ceat_config/ceat-config-v2.yaml --vnf-id $cluster_id --with-network ${ADDARG[@]}
  done
  cd $CWD
}


function rebase_ts_config()
{
  local CWD=`pwd`
  cd $BASEDIR/../ts-config
  branch=$(git rev-parse --abbrev-ref HEAD)
  if git pull --rebase >/dev/null 2>&1;then
    echo "Rebase 'ts-config' [$branch] repo successfully."
  else
    echo "Error: failed to rebase 'ts-config'"
    exit 1
  fi
  cd $CWD
}


function main()
{
  # generate ccd config via CEAT
  echo "Generating CCD configuration by CEAT tool"
  gen_ccd_config $@
  echo "Generating CCD configuration by CEAT tool DONE!"

  # rebase ts config repo
  rebase_ts_config

  #enter to root dir
  cd $BASEDIR/..

  T1_CONFIGDIR=(lab/n280/eccd1 lab/n280/eccd3 lab/n99/eccd1)

  for cluster_dir in ${T1_CONFIGDIR[@]}
  do
    for directory in $(find ${cluster_dir} -mindepth 1 -maxdepth 1 -type d)
    do
      if [[ $directory == "${cluster_dir}/eccd" ]];then
        continue
      fi
      CWD=`pwd`
    echo Entering to $directory
      if [[ $directory == "${cluster_dir}/eccd" ]];then
        continue
      fi
      cd $directory
      echo Generate CNF configuration by \"cnat -g\" CLI
      if cnat -g >/dev/null 2>&1;then
        echo Generated CNF configuration successfully
      else
        echo Error: failed to generate with non-zero return
      break
      fi
      cd $CWD
    done
  done
}

## main function
main $@
