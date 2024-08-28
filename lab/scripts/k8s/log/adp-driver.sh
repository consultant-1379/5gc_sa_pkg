#!/bin/bash
#set -x
############################################################################
# organization "Ericsson AB";                                              #
# contact " ADP Support via mail";                                         #
# description "Script to drive collect_ADP_logs.sh for adc.                #
#        Copyright (c) 2023 Ericsson AB. All rights reserved.";            #
############################################################################
# Author: Dekuan Kong.                                        #
#                                                                          #
# Script to drive collect_ADP_logs.sh for adc                              #
# NOTE!!!: Must comment the function invokation in collect_ADP_logs.sh        #

# adp-driver <namespace>  <opt_min_to_collect>                             #
#                                                                          #
############################################################################

############################################################################
#                          History                                         #
#                                                                          #
#                                                                          #
# 2023-03-3 edekkon      Invoke version: 2023-02-10   Version 1.0.13       #
#                                                                          #
############################################################################

tmp_file=$(mktemp)
trap "rm -rf $tmp_file" EXIT

#######validate count of parameters
all_namespaces="pcc1 pcc2 pcg ccrc ccdm ccsm ccpc cces sc eda evnfm kube-system"

time=30m
if [ $# -eq 1 ];then
  if [[ \"$1\" =~ [0-9]{1,}[smh] ]];then
    for ns in $all_namespaces
    do
      kubectl get namespaces $ns >/dev/null 2>&1
      if [ $? -eq 0 ];then
        namespaces+="$ns "
      fi
    done
    # remove last space char
    namespaces="${namespaces::-1}"
    time=$1
  else
    namespaces=$(echo $1 | tr ',' ' ')
  fi
fi

if [ $# -eq 2 ];then
  namespaces=$(echo $1 | tr ',' ' ')
  if [[ \"$2\" =~ [0-9]{1,}[smh] ]];then
    time=$2
  else
   echo "####################incorrect time format"
   exit 1
  fi
fi


# Validate namespaces

for namespace in $namespaces
  do
  kubectl get namespace $namespace &>/dev/null

    if [ $? != 0 ]; then
      echo "ERROR: The namespace $namespace does not exist. You can use \"kubectl get namespace\" command to verify your namespace"
      echo -e $USAGE
      exit 1
    fi

  done

for namespace in $namespaces;do
  echo "#####################################################"
  source ../lab/scripts/k8s/log/collect_ADP_logs.sh $namespace $time 
  echo "###### base_dir: ${log_base_dir} base_path: ${log_base_path}"

  get_describe_info &
  get_events &
  get_pods_logs &
  get_helm_info &
  diameter_log &
  cmm_log &
  siptls_logs &
  cmy_log &
  diameter_log &
  sm_log &
  echo "$namespace $log_base_dir $log_base_path" >> $tmp_file

done

echo "`date` ADP log collection is ongoing..."
wait
echo "`date` ADP log collection is done, start basic_checks and compress..."

while read  line
do
  namespace=$(echo $line|awk '{print $1}')
  log_base_dir=$(echo $line|awk '{print $2}')
  log_base_path=$(echo $line|awk '{print $3}')
  echo "line ns:$namespace $log_base_dir $log_base_path"
  basic_checks &
done  < $tmp_file

wait

while read  line
do
  namespace=$(echo $line|awk '{print $1}')
  log_base_dir=$(echo $line|awk '{print $2}')
  log_base_path=$(echo $line|awk '{print $3}')
  echo "line ns:$namespace $log_base_dir $log_base_path"
  compress_files &
  wait
done  < $tmp_file
