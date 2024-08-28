#-------------------------------------------------------------------------------------------
# Description: The script is for 5GC CNFs Healthcheck.                                     -
# Author     : dekuan.kong@ericsson.com                                                    -
# version    : 1.11                                                                        -  
# Reference  : 5GC CNFs CPI Health Check                                                   -  
#-------------------------------------------------------------------------------------------

#!/usr/bin/env bash


##############################################################################
########### run the script on Traffic Cluster Director for 5GC CNF Healthcheck###
##############################################################################
VERSION=v1.11

# 0: don't collect pod log when CNF in unhealthy state
# 1: Collect pod log when CNF in unhealthy state 
COLLECT_POD_LOG_FLAG=0
##### Functions definitions 

# background color
BG_RED="41"
BG_GREEN="42"
BG_YELLOW="43"
BG_BLUE="44"
BG_VIOLET="45"
BG_SKYBLUE="46"
BG_WHITE="47"

function debug()
{
    echo -e "\033[37m$(date +%Y%m%d-%H:%M:%S-%Z  -u) DEBUG:$1\033[0m"
}
function log_info()
{
    echo -e "\033[32m$(date +%Y%m%d-%H:%M:%S-%Z  -u) INFO:$1\033[0m"
}
function warn()
{
    echo -e "\033[33m$(date +%Y%m%d-%H:%M:%S-%Z  -u) WARN:$1\033[0m"
}
function log_error()
{
    echo -e "\033[31m$(date +%Y%m%d-%H:%M:%S-%Z  -u) ERROR:$1\033[0m"
}


function usage() {
  echo;
  log_info 'Description: It is for 5GC CNFs HealthCheck, one at a time.'
  log_info 'usage: ./fivegc_cnf_healthcheck.sh <namespace> <testing Description>'
  log_info 'usage: Example: ./fivegc_cnf_healthcheck.sh ccdm1 or ./fivegc_cnf_healthcheck.sh ccdm "before testing"'
  log_info 'usage: Version: ./fivegc_cnf_healthcheck.sh -v'
  echo;
}

# output the result information for each Healthcheck item
# param : the core information to output 
function format_slogan() {
  datetime=`date "+%Y-%m-%d %H:%M:%S"`
  ret_info=$*
  len=`expr $(echo $ret_info | awk '{print length($0)}') + 30 `
  echo |tee -a  $REPORT_FILE
  seq -s "*" ${len}|sed -E "s/[0-9]//g" |tee -a $REPORT_FILE
  echo "***" ${ret_info} " ${datetime} ***"   |tee -a $REPORT_FILE
  seq -s "*" ${len}|sed -E "s/[0-9]//g" |tee -a $REPORT_FILE

}



# check_alarms <namespace>
# return : ret 0:no alarm;  1:at least one alarm exists
function check_alarms() {
  format_slogan "start checking alarms for $1"
  if [ $# -ne 1 ]
  then 
    echo "### Check_alarms:FAIL, Param is wrong" | tee -a $REPORT_FILE
    return 1
  else
    CNF_NS=$1
    alarms_list=$(kubectl -n ${CNF_NS} exec -it $(kubectl -n ${CNF_NS} get pods -l app=eric-fh-alarm-handler | grep -v topics | tail -1 | awk '{print $1}') -c eric-fh-alarm-handler -- ah_alarm_list.sh -f | tee -a $REPORT_FILE)
    #echo "### check_alarms ${CNF_NS}-->alarm_list:${alarms_list} "
    log_info "The alarm information:" >> ${Detailed_LOG}
    echo "$alarms_list"  >> ${Detailed_LOG}
    alarm_exists=$(echo $alarms_list |grep -i alarmName)
    if [[ $alarm_exists == "" ]]
    then
	log_info "check_alarms $CNF_NS : No alarm found, Good!" |tee -a $REPORT_FILE
        return 0
    else
        file_name="exception-alarms.conf"
        file_path="${HOME}/.sputils/k8s/fivegc-cnf-healthcheck/$file_name"
        if [ -e $file_name ]
        then 
          file_path=$file_name
        fi
        CNF_NAME=$(echo "$CNF_NS" | sed 's/[0-9]//g')
        cnf_in_exception=$(cat ${file_path} |grep -v CNF-NAME |grep -i $CNF_NAME) 
        if [[ "$cnf_in_exception" == "" ]]
        then
            log_error "Alarm list:$alarms_list"
            return 1
        else
            exception_alarms=$(cat ${file_path} |grep -v CNF-NAME |grep -i $CNF_NAME |awk '{print $2}')
            #echo "CNF_NAME: $CNF_NAME, exception_alarms: $exception_alarms"
            alarms_unexpected=$(echo $alarms_list |grep -vE $exception_alarms)
            if [[ "$alarms_unexpected" == "" ]]
            then
                log_info "check_alarms ${CNF_NS}: No unexpected alarm exists except: ${exception_alarms}" | tee -a $REPORT_FILE
                return 0
            else
                log_error "Alarm list:$alarms_list"
                return 1	
            fi
        fi
    fi
  fi
}

#Description: It's for checking PVC usage using df command
#              The usage percentage must be below 80%.
#Param       : The namespace
#Return      : 0 means pass, 1 means failed

function check_pvc_usage() {
  namespace=$1
  pvc_usage_threshold=80
  result=0
  format_slogan "Check PVC usage in namespace $namespace"
  log_info "The PVC usage information:" >> ${Detailed_LOG}
  counter=0
  for pvc in $(kubectl -n $ns get pvc |grep -v NAME | awk '{print $1}');
  do
  let "counter++"
  if [[ $counter -gt 9 ]]
  then
    counter=0
    sleep 5
  fi
  (
    podname=$(kubectl -n $ns describe pvc $pvc |grep 'Used By:' |awk '{print $3}');
    volumn=$(kubectl -n $ns describe pod $podname |grep -B2 "ClaimName:  $pvc" |sed -n '1p' | awk '{print $1}'| cut -d ":" -f 1)
    mount_dir=$(kubectl -n $ns describe pod $podname | grep -v "/etc/openldap/old.slapd.d" | grep "from $volumn (rw" | sed -n '1p' | awk '{print $1}')
    #echo "### $mount_dir from volume:${volumn} "
    pvc_usage=$(kubectl -n $ns exec -q $podname -- df -h | grep -v 'Filesystem' | grep 'dev' | grep $mount_dir |awk '{print $5}' | cut -d "%" -f 1);
    echo "pvc:$pvc Used By pod:$podname, usage:${pvc_usage}%, detailed: " $(kubectl -n $ns exec -q $podname -- df -h | grep -v 'Filesystem' | grep 'dev'  | grep $mount_dir ) >> ${Detailed_LOG}

    if [[ ${pvc_usage} -ge $pvc_usage_threshold ]]
    then
      echo "The pvc ${pvc} usage(Used By $podname):${pvc_usage}% is NOT below ${pvc_usage_threshold}%." | tee -a $REPORT_FILE
      echo 1 > f_pvc_usage_flag_rjdhd
    fi
  ) &
  done
  wait
  if [ -e f_pvc_usage_flag_rjdhd ]
  then
    result=1
    rm f_pvc_usage_flag_rjdhd
  fi
  if [[ $result -eq 0 ]]
  then
    log_info "The usage of all the Persistent Volume Claim is below ${pvc_usage_threshold}%." |tee -a $REPORT_FILE
  else
    log_error "Not all the Persistent Volume Claim usage is below ${pvc_usage_threshold}%." |tee -a $REPORT_FILE
  fi
  return $result

}

#Description:  Check CPU Usage on Pod Level
#              the usage in every pod must be below 80%
#Param       : The namespace
#Return      : 0 means pass, 1 means failed

function check_cpu_usage_pod_level() {
  ns=$1
  cpu_usage_threshold=80
  result=0
  pcg_exception_pod_list="pc-up-data-plane"

  format_slogan "Check pods cpu usage in namespace $ns by promtool"

  if [[ "$(echo $ns | tr 'A-Z' 'a-z')" =~ "pcg" ]]
  then
    log_info "The cpu usage of pods:$pcg_exception_pod_list would not be checked."  | tee -a $REPORT_FILE
  fi
  if [[ "$(echo $ns | tr 'A-Z' 'a-z')" =~ "sc" ]]
  then
    warn "The SC does not have pmrm_container_cpu counters so far, trying to find other way."  | tee -a $REPORT_FILE
    return 0
  fi
  cpu_usages=$(kubectl -n ${ns} exec sts/eric-pm-server --container eric-pm-server -- promtool query instant "http://localhost:9090" "((sum by (pod)((pmrm_container_cpu_usage_nanocore{kubernetes_namespace=\"${ns}\"}))/(sum by (pod)((pmrm_container_cpu_limits_nanocore{kubernetes_namespace=\"${ns}\"} > 0)))) * 100 or vector(0))"|tr '"' ' '|sort -r -g -k5|awk '/pod/ {print $2,$5} ')
  if [ "$cpu_usages" = "" ]
  then
    log_error "Failed to get the pods cpu usage data by promtool." | tee -a $REPORT_FILE
    return 1
  fi
  max=$(echo "$cpu_usages" |grep -vE "$pcg_exception_pod_list" | awk '{print $2}' | head -n 1)
  max=`echo ${max%.*}`
  #echo "max:$max"
  log_info "pods cpu usage:" >> ${Detailed_LOG}
  echo "${cpu_usages}" >> ${Detailed_LOG}
  if [[ $max -ge $cpu_usage_threshold ]]
  then
    echo "$cpu_usages" |grep -vE "$pcg_exception_pod_list" |awk -v var1=$cpu_usage_threshold '{if ($2 >= var1) print $0}' | tee -a $REPORT_FILE
    log_error "The cpu usage of some pods(max:${max}%) are equal or higher than ${cpu_usage_threshold}%."  | tee -a $REPORT_FILE
    result=1
  else
    log_info "The cpu usage of all the pods(max:${max}%) are lower than ${cpu_usage_threshold}%."   | tee -a $REPORT_FILE
  fi

  return $result
  
}

#Description:  Check memory Usage on Pod Level
#              the usage in every pod must be below 80%
#Param       : The namespace
#Return      : 0 means pass, 1 means failed

function check_mem_usage_pod_level() {
  ns=$1
  mem_usage_threshold=80
  result=0
  format_slogan "Check pods memory usage in namespace $ns by promtool"
  if [[ "$(echo $ns | tr 'A-Z' 'a-z')" =~ "sc" ]]
  then
    warn "The SC does not have pmrm_container_mem counters so far, trying to find other way."  | tee -a $REPORT_FILE
    return 0
  fi

  mem_usages=$(kubectl -n $ns exec eric-pm-server-0 --container eric-pm-server -- promtool query instant "http://localhost:9090" "((sum by (pod)((pmrm_container_mem_usage_bytes{kubernetes_namespace=\"$ns\"}))/(sum by (pod)((pmrm_container_mem_limits_bytes{kubernetes_namespace=\"$ns\"}) > 0))) * 100 or vector(0))"|tr '"' ' '|sort -r -g -k5|awk '/pod/ {print $2,$5} ')
  if [ "$mem_usages" = "" ]
  then
    log_error "Failed to get the pods memory usage data by promtool."
    return 1
  fi
  max=$(echo $mem_usages | awk '{print $2}')
  max=`echo ${max%.*}`
  log_info "pods mem usage:" >> ${Detailed_LOG}
  echo "${mem_usages}" >> ${Detailed_LOG}
  if [[ $max -ge $mem_usage_threshold ]]
  then
    echo "$mem_usages" | awk -v var1=$mem_usage_threshold '{if ($2 >= var1) print $0}' | tee -a $REPORT_FILE
    log_error "The mem usage of some pods(max:${max}%) is equal or higher than ${mem_usage_threshold}%."  | tee -a $REPORT_FILE
    result=1
  else
    log_info "The mem usage of all the pods(max:${max}%) is lower than ${mem_usage_threshold}%."   | tee -a $REPORT_FILE
  fi

  return $result
  
}



#Description:  Check CPU&memory Usage on worker node Level
#              the overall worker nodes cpu usage must be below 80%
#Param       : The namespace
#Return      : 0 means pass, 1 means failed

function check_cpu_mem_usage_worker_level() {
  usage_threshold=90
  result=0
  format_slogan "Check cpu usage on worker node level"
  worker_nodes_desc=$(kubectl describe nodes -l node-role.kubernetes.io/worker --chunk-size 0)
  sum_worker_cpu_allocatable=$(echo "$worker_nodes_desc" | grep -A5 '^Allocatable:$'| egrep -i "cpu:" | awk '{sum=sum+$2} END { print sum*1000}')
  sum_worker_cpu_used=$(echo "$worker_nodes_desc" | egrep "cpu " | awk '{sum=sum+$2} END {print sum}')
  usage_percentage=$((${sum_worker_cpu_used}*100/${sum_worker_cpu_allocatable}))
  log_info "worker nodes allocatable cpu:" >> ${Detailed_LOG}
  echo "$worker_nodes_desc"  | grep -A5 '^Allocatable:$'| egrep -i "cpu" >> ${Detailed_LOG}
  log_info "worker nodes used/Requests cpu:" >> ${Detailed_LOG}
  echo "Resource           Requests        Limits" >> ${Detailed_LOG}
  echo "$worker_nodes_desc" | egrep "cpu " >> ${Detailed_LOG}
  log_info "Sum of workers cpu: ${sum_worker_cpu_allocatable}, sum of used/Requests:${sum_worker_cpu_used}, usage:${usage_percentage}%" >> ${Detailed_LOG}
  usage_percentage=`echo ${usage_percentage%.*}`
  if [[ $usage_percentage -ge $usage_threshold ]]
  then
    log_error "The overall cpu usage/Requests of worker nodes ${usage_percentage}% is equal or higher than ${usage_threshold}%."  | tee -a $REPORT_FILE
    result=1
  else
    log_info "The overall cpu usage/Requests of worker nodes ${usage_percentage}% is lower than ${usage_threshold}%."   | tee -a $REPORT_FILE
  fi

  format_slogan "Check memory usage on worker node level"
  sum_worker_mem_allocatable=$(echo "$worker_nodes_desc"  | grep -A5 '^Allocatable:' | egrep -i "memory:" | awk '/Ki/ { a=$2*1024}; /Mi/ { a=$2*1024*1024 }; /M/ { a=$2*1000*1000 }; /Gi/ { a=$2*1024*1024*1024 }; /G/ { a=$2*1000*1000*1000 }; {a=$2}; {sum=sum+a}  END { sum=sum/1024/1024; printf "%2.0f", sum }')
  sum_worker_mem_used=$(echo "$worker_nodes_desc" |grep -A5 "Allocated resources:" |  egrep "memory " | awk '/Ki/ { a=$2*1024}; /Mi/ { a=$2*1024*1024 }; /M/ { a=$2*1000*1000 }; /Gi/ { a=$2*1024*1024*1024 }; /G/ { a=$2*1000*1000*1000 }; {a=$2}; {sum=sum+a} END {sum=sum/1024/1024; printf "%2.0f", sum}')


  usage_percentage=$((${sum_worker_mem_used}*100/${sum_worker_mem_allocatable}))
  log_info "worker nodes allocatable memory:" >> ${Detailed_LOG}
  echo "$worker_nodes_desc"  | grep -A5 '^Allocatable:' | egrep -i "memory:" >> ${Detailed_LOG}
  log_info "worker nodes used/Requests memory:" >> ${Detailed_LOG}
  echo "Resource           Requests        Limits" >> ${Detailed_LOG}
  echo "$worker_nodes_desc" |grep -A5 "Allocated resources:" | egrep "memory " >> ${Detailed_LOG}
  log_info "Sum of workers memory: ${sum_worker_mem_allocatable}, sum of used/Requests:${sum_worker_mem_used}, usage:${usage_percentage}%" >> ${Detailed_LOG}
  usage_percentage=`echo ${usage_percentage%.*}`
  if [[ $usage_percentage -ge $usage_threshold ]]
  then
    log_error "The overall mem usage/Requests of worker nodes ${usage_percentage}% is equal or higher than ${usage_threshold}%."  | tee -a $REPORT_FILE
    result=1
  else
    log_info "The overall mem usage/Requests of worker nodes ${usage_percentage}% is lower than ${usage_threshold}%."   | tee -a $REPORT_FILE
  fi
  return $result
  
}


function check_product_liense_state() {
  namespace=$1
  ret=0
  format_slogan "Check ${namespace^^} license(pcc,pcg,sc,eda not verified yet)"
  productType=$(echo ${namespace} |grep -ioE "ccrc|ccdm|ccsm|cces|ccpc|pcc|pcg|sc|eda")
  licenses_state_all=$(kubectl -n $namespace exec -ti $(kubectl get po -n $namespace|grep -v Completed|grep cm-mediator|grep -v notifier|awk '{print $1}'|head -n1) -- curl -ss --header "Content-Type: application/json" --request GET eric-lm-combined-server:8080/license-manager/api/v1/licenses --data "{\"productType\":\"${productType^^}\"}")
  log_info "Detailed ${productType^^} license info:" >> ${Detailed_LOG}
  echo "$licenses_state_all"|jq . >> ${Detailed_LOG}
  if [[ "$licenses_state_all" =~ "Unsupported product type" || "$licenses_state_all" = "" ]]
  then 
    warn "The ${productType^^} does not support query license info from license-manager right now."
    return $ret
  fi

  licenses_state=$(echo "${licenses_state_all}"|jq -r '.licensesInfo[]|"\(.license.keyId) \(.licenseStatus)"')
  license_num=$(echo "$licenses_state"|wc -l)
  valid_license_num=$(echo "$licenses_state"|grep " VALID" | wc -l)
  if [[ $license_num -eq $valid_license_num ]]
  then
    log_info "All the ${license_num} ${productType^^} licenses are VALID."  | tee -a $REPORT_FILE
  else
    log_error "Not all the ${license_num} ${productType^^} licenses are VALID."  | tee -a $REPORT_FILE
    ret=1      
  fi
  return $ret

}

#Description : Check the CCXX system status
#              for CCDM, CCRC, CCPC    
#Param       : namespace
function check_system_status() {
  ns=$1
  ret=0
  
  nodes=()
  sys_state_list=("operational-state" "administrative-state")
  sys_expected_ret_list=("enabled" "unlocked")
  
  cnf_name=$(echo $ns |grep -ioE "ccdm|ccrc|ccpc")
  case $cnf_name in
    ccdm)
      nodes[0]=udr
      sys_state_list[2]="availability-error"
      sys_expected_ret_list[2]="[]"
    ;;
    ccrc)
      nodes[0]=nrf
      nodes[1]=nssf
      warn "The product CCRC does not provide the state of 'availability-status' yet!"
    ;;
    ccpc)
      nodes[0]=pcf
      sys_state_list[2]="availability-status"
      sys_expected_ret_list[2]="[]"
    ;;

  esac
 
  for node in ${nodes[@]}
  do
    url=http://localhost:5003/cm/api/v1/configurations/ericsson-${node}
    key="ericsson-${node}:${node}"
    all_node_sys_info=$(kubectl exec --namespace $ns  $(kubectl get pods --namespace $ns |egrep -m 1 "eric-cm-mediator-[a-f,0-9]"|awk '{print $1}')  -c eric-cm-mediator -- curl -s ${url})
    log_info "The detailed system status information of ${key}" >> ${Detailed_LOG}
    echo "${all_node_sys_info}" >> ${Detailed_LOG}
    for(( i=0;i<${#sys_state_list[@]};i++ ))
    do
      slogan="${cnf_name^^} ${node^^} ${sys_state_list[i]}"
      format_slogan "Check $slogan"
      state_ret=$(echo "${all_node_sys_info}" | jq --arg KEY $key --arg STATE ${sys_state_list[i]} -r '.data[$KEY][$STATE]'|tee -a $REPORT_FILE )
      if [ "$state_ret" = "${sys_expected_ret_list[i]}" ]
      then
        log_info "The $slogan is ${sys_expected_ret_list[i]}." | tee -a $REPORT_FILE
      else
        log_error "The $slogan is NOT ${sys_expected_ret_list[i]} but ${state_ret} instead." | tee -a $REPORT_FILE
        ret=1
      fi  
    done
  done
  return $ret

}

#Description : the Function is only for checking CCDM UDR relative status 
#Param       : The name of the ccdm namespace
function check_ccdm_udr_system_status() {
  ccdm_ns=$1
  ret=0

  format_slogan "Check CCDM UDR System status."
  url_prefix="-- curl http://localhost:8080/udr-status/v1/tree?path=/udr/"
  
  # refer to CCDM CPI   
  items_name_list[0]="Check UDR status"
  items_name_list[1]="Check message bus status"
  items_name_list[2]="Check Nudr FE status"
  items_name_list[3]="Check LDAP FE status"
  items_name_list[4]="Check LDAP Balancer status"
  items_name_list[5]="Check SOAP Notifchecker status"
  items_name_list[6]="Check SOAP Notifsender status"
  items_name_list[7]="Check REST Notifchecker status"
  items_name_list[8]="Check REST Notifsender status"
  items_name_list[9]="Check REST Notifsubscription status"
  items_name_list[10]="Check provisioning FE status"
  items_name_list[11]="Check gudrest FE status"
  items_name_list[12]="Check provsync FE status"
  items_name_list[13]="Check DBmanager status"
  items_name_list[14]="Check DBmonitor status"
  
  items_url_list[0]="status"
  items_url_list[1]="reporting/messageBusMonitor"
  items_url_list[2]="reporting/nudrFe"
  items_url_list[3]="reporting/ldapFe"
  items_url_list[4]="reporting/ldapBalancer"
  items_url_list[5]="reporting/SOAPnotifchecker"
  items_url_list[6]="reporting/SOAPnotifsender"
  items_url_list[7]="reporting/RESTnotifchecker"
  items_url_list[8]="reporting/RESTnotifsender"
  items_url_list[9]="reporting/RESTnotifsubscription"
  items_url_list[10]="reporting/provisioningFE"
  items_url_list[11]="reporting/gudrestFe"
  items_url_list[12]="reporting/provsyncFe"
  items_url_list[13]="reporting/dbManager/status"
  items_url_list[14]="reporting/dbMonitor/status"
  
  udr_sys_stat_provider="eric-udr-system-status-provider"
  status_counter_name=${#items_name_list[*]}
  status_counter_url=${#items_url_list[*]}
  if [ $status_counter_name -ne $status_counter_url ]
  then 
    log_error "The counter of CCDM source data:name and url is mismatch,plese check"
    ret=1
  else
    for k in $(seq 0 `expr $status_counter_name - 1 `)
    do
      format_slogan ${items_name_list[$k]}
      status=$(kubectl exec --namespace $ccdm_ns deploy/$udr_sys_stat_provider -c $udr_sys_stat_provider ${url_prefix}${items_url_list[$k]} | jq . |tee -a $REPORT_FILE )
      if [ -n "$(echo $status |grep -E 'OK|STARTED')" ]
      then
        log_info "${items_name_list[$k]} ,the status is OK|STARTED " | tee -a $REPORT_FILE
      else
        log_error "${items_name_list[$k]} , the status is NOT OK." | tee -a $REPORT_FILE
        ret=1
      fi
    done
  fi
  format_slogan "Get a summary with DBmonitor information(NO Checking)."
  db_monitor_info=$(kubectl exec --namespace $ccdm_ns deploy/$udr_sys_stat_provider -c $udr_sys_stat_provider ${url_prefix}"reporting/dbMonitor/summary" | jq . |tee -a $REPORT_FILE )
  format_slogan "Check the status of the replication channels for remote instance (NO Checking)."
  remote_instance_status=$(kubectl exec --namespace $ccdm_ns deploy/$udr_sys_stat_provider -c $udr_sys_stat_provider ${url_prefix}"reporting/dbMonitor/replication/2" | jq . |tee -a $REPORT_FILE )

  return $ret
 
}


##########################################################################################
############################### MAIN #####################################################
##########################################################################################
#NF's namespace
ns=$1


#used to add testing information to log directory name.
test_Description=""
#wanted_param_num=1

# flag_summary 0:means the system is healthy ; 1: means unhealthy
flag_summary=0

if [  "$1" = "-h"  -o  "$1" = "--help"  ]; then 
  usage
  exit 1 
elif [ "$1" = "-v" ]
then
 echo $VERSION
 exit 0
fi


if [ $# -eq 1  ] 
then 
  #Print the welcome information
  slogan="Hi, You are running: \"$0 ${ns}\" (${VERSION}) on $(hostname) ,Have fun!"
  format_slogan $slogan
elif [ $# -eq 2 ] #add the testing information to the log directory name 
then
  test_Description=$(echo $2 |sed -e 's/[ ][ ]*/-/g')
  #Print the welcom information
  slogan="Hi, You are running: \"$0 ${ns} ${test_Description}\" (${VERSION}) on $(hostname) ,Have fun!"
  format_slogan $slogan 
else
  log_error "The actual param num:$# is wrong, the expected is ${wanted_param_num}" 
  usage
  exit 1
fi

# define the report log file and delete the old one
current_time=$(date "+%Y%m%d%H%M%S")
REPORT_DIR="$(pwd)/fivegc-healthcheck-logs/${ns}_healthcheck-${test_Description}-${current_time}"
if [ ! -d $REPORT_DIR ]
then 
  mkdir -p $REPORT_DIR
fi

REPORT_FILE=${REPORT_DIR}"/healthcheck-report-${ns}.log"
# save the detailed information for troubleshooting
Detailed_LOG=${REPORT_DIR}/detailed-info-${ns}.log
echo "The detailed information of $ns" > ${Detailed_LOG}


check_alarms $ns
flag_summary=$?


format_slogan "Check Kubernetes nodes state"
kubectl get nodes |tee -a $REPORT_FILE

nodes_state="$(kubectl get nodes | grep -v 'NAME'|awk '{if ($2!="Ready") print $0}')"

# check if the return node list empty or not : empty is expected 
if [ ${#nodes_state} -ne 0 ]
then
  log_error "Some k8s nodes are NOT in 'Ready' state!" |tee -a $REPORT_FILE
  flag_summary=1
else
  log_info "All the K8s nodes are in 'Ready' state." |tee -a $REPORT_FILE
fi


check_cpu_mem_usage_worker_level
worker_cpu_usage_ret=$?

if [ $worker_cpu_usage_ret -gt 0 ]
then
  flag_summary=1  
fi

format_slogan "Check $ns Pods State"
pod_state=$(kubectl -n $ns get po -o wide | grep -vE 'Running|STATUS|Completed' | tee -a ${REPORT_FILE} )


# if pod_state is empty ,that means all pods state is normal 
if [ -z "$pod_state"  ] 
then 
  log_info "All Pods are in Running or Completed state."|tee -a $REPORT_FILE
else 
  log_error "NOT all Pods are in Running or Completed state " |tee -a $REPORT_FILE
  echo "NAME                                                          READY   STATUS             RESTARTS   AGE     IP                NODE                              NOMINATED NODE   READINESS GATES"
  echo  "$pod_state"

  flag_summary=1

fi

format_slogan "Check $ns Containers State"
container_state=`kubectl -n $ns get po | grep -v Completed | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$3) { found=1; print $0}} END { if (!found) print "All containers are up."}'`

if [ "$container_state" != "All containers are up." ]
then
  log_error "Some of the Containers are not up." |tee -a $REPORT_FILE
  flag_summary=1
  kubectl -n $ns get po | grep -v Completed | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$3) { found=1; print $0}} END { if (!found) print "All containers are up."}'

else
  log_info "All containers are up." |tee -a $REPORT_FILE

fi


format_slogan "Check $ns Replicas State"
replica_state=`kubectl -n $ns get deploy | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$3) { found=1; print $0}} END { if (!found) print "All desired replicas are ready"}' `

if [ "$replica_state" != "All desired replicas are ready" ]
then
  log_error "Some of the Desired Replicas are NOT in Ready Status." |tee -a $REPORT_FILE
  flag_summary=1
  kubectl -n $ns get deploy | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$3) { found=1; print $0}} END { if (!found) print "All desired replicas are ready"}'
else
  log_info "All the Desired Replicas are in Ready Status." |tee -a $REPORT_FILE
fi

format_slogan "Check $ns statefulsets Replicas State"
replica_state_sts=`kubectl -n $ns get statefulsets | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$3) { found=1; print $0}} END { if (!found) print "All desired replicas are ready"}' `

if [ "$replica_state_sts" != "All desired replicas are ready" ]
then
  log_error "Some of the Desired statefulsets Replicas are NOT in Ready Status." |tee -a $REPORT_FILE
  flag_summary=1
  kubectl -n $ns get statefulsets | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$3) { found=1; print $0}} END { if (!found) print "All desired replicas are ready"}'
else
  log_info "All the Desired statefulsets Replicas are in Ready Status." |tee -a $REPORT_FILE
fi

format_slogan "Check $ns daemonsets Replicas State"
replica_state_daem=`kubectl -n $ns get daemonsets | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$3) { found=1; print $0}} END { if (!found) print "All desired replicas are ready"}' `

if [ "$replica_state_daem" != "All desired replicas are ready" ]
then
  log_error "Some of the Desired daemonsets Replicas are NOT in Ready Status." |tee -a $REPORT_FILE
  flag_summary=1
  kubectl -n $ns get daemonsets | awk -F"[ /]+" 'BEGIN{found=0} !/NAME/ {if ($2!=$4) { found=1; print $0}} END { if (!found) print "All desired replicas are ready"}'
else
  log_info "All the Desired daemonsets Replicas are in Ready Status." |tee -a $REPORT_FILE
fi

format_slogan "Check pods/containers restarts."

# output the pods that restart-count > 0
kubectl -n $ns get po  | head -1 | tee -a $REPORT_FILE
kubectl -n $ns get po  | grep -v NAME |awk '$4>0' | sort --reverse --key 4 --numeric
pods_restart=`kubectl -n $ns get po  | grep -v NAME |awk '$4>0' | sort --reverse --key 4 --numeric |tee -a  $REPORT_FILE `


criterion_restarts=2
max_restart_count=$(kubectl -n $ns get po | (sed -u 1q; sort --reverse --key 4 --numeric) | egrep "\([1-5]?[0-9]m ago|[0-9]s ago" | awk '{print $4}' | sed -n '2p')


if [ -n "$max_restart_count" ] && [[ $max_restart_count -gt ${criterion_restarts} ]]
then
  log_error "Some pods/containes restart more than $criterion_restarts times during the last 1 hour."  |tee -a $REPORT_FILE
  flag_summary=1
else
  log_info "There is not any pod/container restart more than $criterion_restarts times during the last 1 hour."  |tee -a $REPORT_FILE

fi

format_slogan "list the Software Versions(no auto checking here) "
helm list -n $ns | tee -a  $REPORT_FILE


format_slogan "Check Persistent Volume Claim status "


pvc_state="$(kubectl -n $ns get pvc | awk '{if (($2 == "Bound")) {printf "%s\t%s\n", $0,"0"} else {printf "%s\t%s\n",$0,"1"}} '| grep -v NAME | awk '{SUM+=$8}END{if (SUM>0){print "NOT OK"}else{print "OK"}}' | tee -a $REPORT_FILE )"

pvc_count=$(kubectl -n $ns get pvc | grep -v NAME | wc -l)
if [[ $pvc_count -eq 0 ]]
then
  warn "It seems no PVC applicable." |tee -a $REPORT_FILE
fi


# check if the return data is  empty or not : empty is expected
if [ "${pvc_state}" = "NOT OK" ]
then
  log_error "Some of the Persistent Volume Claim are NOT in Bound Status!" |tee -a $REPORT_FILE
  flag_summary=1
elif [ "${pvc_state}" = "OK" ]
then
  log_info "All the Persistent Volume Claim are in Bound Status." |tee -a $REPORT_FILE
fi

if [[ $pvc_count -gt 0 ]]
then
  check_pvc_usage $ns
  pvc_usage_ret=$?
  if [ $pvc_usage_ret -gt 0 ]
  then
    flag_summary=1
  fi
fi

check_cpu_usage_pod_level $ns
pod_cpu_usage_ret=$?

if [ $pod_cpu_usage_ret -gt 0 ]
then
  flag_summary=1  
fi

check_mem_usage_pod_level $ns
pod_mem_usage_ret=$?

if [ $pod_mem_usage_ret -gt 0 ]
then
  flag_summary=1  
fi

format_slogan "Check backups is NOT applicable"

format_slogan "Check Connection to NeLS"
alarm2check=LicenseManagerAutonomousModeActivated
nels_alarm=$(kubectl -n $ns exec -it $(kubectl -n $ns get pod --no-headers|grep "alarm-handler" |awk '{print $1}') -- ah_alarm_list.sh alarmName=$alarm2check)
if [[ "$nels_alarm" =~ "[]" ]]
then
  log_info "The connection to NeLS server is in normal state." |tee -a $REPORT_FILE
else
  log_error "The connection to NeLS server is lost, please check." |tee -a $REPORT_FILE
  flag_summary=1
fi

format_slogan "Check HPA"

hpa_info=$(kubectl get hpa -n $ns)
hpa_ret=$(kubectl get hpa -n $ns| awk '{ gsub("/"," ",$0); print $0 }' | awk '{ gsub("%"," ",$0); print $0 }'  | awk '{if ($8==0) {printf "%s\t%s\n", $0,"1"} if (($7 <= $8) &&($4 == "<unknown>")) {printf "%s\t%s\n", $0,"1"} if (($7 <= $8) && ($4>$5*0.8))  {printf "%s\t%s\n", $0,"1"} if ($7>$8) {printf "%s\t%s\n", $0,"0"}}' |grep -v NAME | awk '{SUM+=$10}END{if (SUM>0){print "NOT OK"} else{print "OK"};}')

log_info "The HPA information:" >> ${Detailed_LOG}
echo "${hpa_info}" >> ${Detailed_LOG}

if [[ "$hpa_info" = "" ]]
then
  log_info "HPA is NOT APPLICABLE in $ns" |tee -a $REPORT_FILE
elif [[ "$hpa_ret" = "NOT OK" ]]
then
  hpa_ret_no_config=$(for n in `kubectl get hpa -n $namespace | awk -v reverse="\033[7m\033[31m" -v not_ok=" NOT_OK\033[0m" '{ gsub("/"," ",$0); gsub("%"," ",$0); if ($8==0) {print reverse $0 not_ok} else if (($7 <= $8) &&($4 == "<unknown>")) {print reverse $0 not_ok} else if (($7 <= $8) && ($4>$5*0.8)) {print reverse $0 not_ok} else {print $0 " OK"}}'|grep NOT_OK|awk '{print $2"/"$3}'`;do kubectl -n $namespace get $n;done|grep -v NAME|grep -v "0/0"|awk '{print $1 " NOT_OK"}')
  if [[ "$hpa_ret_no_config" != "" ]]
  then
    log_error "The HPA state in $ns is NOT healthy." |tee -a $REPORT_FILE
    flag_summary=1
  else
    warn "Some HPAs are in unknown state because of lack of license or feature deactivation!"  |tee -a $REPORT_FILE
    log_info "All the HPA in $ns is in healthy state." |tee -a $REPORT_FILE
  fi
else
 log_info "All the HPA in $ns is in healthy state." |tee -a $REPORT_FILE
fi  
  
format_slogan "Check Search Engine Logging Repository Status"
search_ret=0
log_info "The Search Engine Logging Repository Status:" >> ${Detailed_LOG}
for pod in `kubectl get pods -n $ns | awk '{print $1}' | grep eric-data-search-engine-data`
do 
  status=$(kubectl -n $ns exec $pod -c data -- esRest GET /_cluster/health?pretty | grep status)
  ret=$(echo "$status" |grep "green")
  echo "$pod, $status" >> ${Detailed_LOG}
  if [[ "$ret" = "" ]]
  then
    search_ret=1
  fi
done

if [[ $search_ret -eq 0 ]]
then 
  log_info "The Search Engine Logging Repository Status is healthy."  |tee -a $REPORT_FILE
else
  log_error "The Search Engine Logging Repository Status is NOT healthy." |tee -a $REPORT_FILE
  flag_summary=1
fi

check_product_liense_state $ns
license_ret=$?
if [ $license_ret -gt 0 ]
then
  flag_summary=1
fi


check_system_status $ns
sys_ret=$?
# system status is unexpected
if [ $sys_ret -gt 0 ]
then
  flag_summary=1
fi



# check ccdm udr system status if the current $ns contains or equal to 'ccdm'
if [ -n "$(echo $ns |grep -i ccdm)" ]
then
  check_ccdm_udr_system_status $ns
  udr_sys_ret=$?
  # some udr system status is unexpected
  if [ $udr_sys_ret -gt 0 ]
  then
    flag_summary=1
  fi
fi



# collect and analyze pods logs if the product is not in Healthy state.
POD_LOG_DIR="${REPORT_DIR}/podlogs-$ns"

# Summary the report 
format_slogan "                SUMMARY              "
if [ $flag_summary -gt 0 ]
then 
  log_error "### Summary: Oh,The $ns is NOT in Healthy State, Please check the logs in $REPORT_DIR for more info." |tee -a $REPORT_FILE
  if [ $COLLECT_POD_LOG_FLAG -gt 0 ]
  then 
    log_info "start collecting Pods logs for troubleshooting..."
    mkdir -p $POD_LOG_DIR
    for POD in `kubectl get pods -n $ns |grep -v NAME |awk '{print $1}'`;do echo $POD; kubectl logs $POD -n $ns  --all-containers > ${POD_LOG_DIR}/$POD.log;done
    error_logs_num=$(grep '"severity": "error"' ${POD_LOG_DIR}/*.log |wc -l)
    log_info "collect Pods logs DONE and there are $error_logs_num severity:error in pod logs."
    log_info "NOTE:You may set COLLECT_POD_LOG_FLAG=0 to disable the pod log collection FUNC."
  else
    log_info "NOTE:pod logs collection FUNC is disabled ,you may set COLLECT_POD_LOG_FLAG=1 to enable it."
  fi

else
  log_info "### Summary: Congratulations!, The $ns is in Healthy State, Please check the logs in $REPORT_DIR for more info." |tee -a $REPORT_FILE

fi

echo; echo 

log_info "****************************************************" >> ${Detailed_LOG}
log_info "The output of kubectl -n $ns get all       *" >> ${Detailed_LOG}
log_info "****************************************************" >> ${Detailed_LOG}
kubectl get all -n $ns >> ${Detailed_LOG}

exit $flag_summary
