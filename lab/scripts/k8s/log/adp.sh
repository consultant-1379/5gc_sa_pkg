#!/bin/bash
set -x
############################################################################
# organization "Ericsson AB";                                              #
# contact " ADP Support via mail";                                         #
# description "Script to collect ADP logs for Support.                     #
#        Copyright (c) 2020 Ericsson AB. All rights reserved.";            #
############################################################################
# Author: EPRGGGZ Gustavo Garcia G.                                        #
#                                                                          #
# Script to collect logfiles for Kubernetes Cluster based on Spider input  #
# The script wil also collect HELM charts configuration                    #
# To use, execute collect_ADP_logs.sh <namespace>  <opt_min_to_collect>    #
#                                                                          #
############################################################################

############################################################################
#                          History                                         #
#                                                                          #
# 2021-03-26 EPRGGGZ    Added InternalCertificates                         #
#                                                                          #
# 2021-03-18 XKHADOA    Added collection of container init of all PODs     #
#                       Added check POD status before invoke exec the POD  #
#                       Added check if container is restarted              #
#                       Fixed event logs missing                           #
#                       Removed v option in tar command                    #
#                                                                          #
# 2021-02-19 EPRGGGZ    Added option to collect only certain amount of min #
#                       Added collection of container init for DCED        #
#                                                                          #
#                       Improvement on the basic checks                    #
# 2020-10-19 EPRGGGZ    Added information for ssd for CMYP                 #
# 2020-10-19 EPRGGGZ    Added information for basic health check on SE     #
#                                                                          #
# 2020-09-11 EPRGGGZ    Added information for init containers on KMS       #
#                                                                          #
# 2020-06-12 EPRGGGZ    Added support for helm 3 and helm 2                #
#                       Corrected problem on helm get                      #
#                       Added collection of Schemas and configurations CMM #
#                       Added collection init certificate SIP/TLS and KMS  #
#                       Added collection of previous logs from pods        #
#                       Added collection of envionment variables           #
#                       Added Basic checks for quicker troubleshooting     #
#                       Removed execution of obsolete CMYP                 #
#                                                                          #
#                                                                          #
#                                                                          #
#                                                                          #
#                                                                          #
# 2019-09-25  EPRGGGZ    Correcting wrong extension on log output for      #
#                        CMyang provider                                   #
#                                                                          #
# 2019-07-23  EPRGGGZ    Added the log collection for SIP-TLS              #
#                        and CMyang provider                               #
#                                                                          #
# 2019-01-25  EPRGGGZ     Fixed bug with events                            #
#                         Added PV                                         #
#                         Added cmm_logs for CM Mediator                   #
#                                                                          #
#                                                                          #
#                                                                          #
# 2019-01-23   Keith Liu   fix bug when get logs of pod which may have more#
#                          more than one container                         #
#                          add more resources for describe logs            #
#                          add timestamp in the log folder name and some   #
#                          improvement                                     #
#
############################################################################

#Fail if empty argument received
max_cmd=30
tmp_file=$(mktemp)
trap "rm -rf $tmp_file" EXIT
if [[ "$#" = "0" ]]; then
    echo "Wrong number of arguments"
    echo "Usage collect_ADP_logs.sh <Kubernetes_namespace>"
    echo "Optional: collect_ADP_logs.sh <Kubernetes_namespace> <hours/minutes/seconds_to_capture_to_current_time>"
    echo "ex:"
    echo "$0 default    #--- to gather the logs for namespace 'default'"
    echo "Optional: $0 default  30m   #--- to gather the last 30 min of logs for namespace 'default'"
    echo "Optional: $0 default  45s   #--- to gather the last 45 sec of logs for namespace 'default'"
    echo "Optional: $0 default  2h   #--- to gather the last  2 hours of logs for namespace 'default'"
    exit 1
fi


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
#    else
#Create a directory for placing the logs
#log_base_dir=logs_${namespace}_$(date "+%Y-%m-%d-%H-%M-%S")
#log_base_path=$PWD/${log_base_dir}
#mkdir ${log_base_dir}
#Check if there is helm2  or helm3 deployment
#      helm version | head -1 >$log_base_path/helm_version.txt
#      if eval ' grep v3 $log_base_path/helm_version.txt'
#        then
#        echo "HELM 3 identified"
#        HELM='helm get all --namespace='${namespace}
#   #    echo $HELM
#      else
#        HELM='helm get --namespace='${namespace}
#       echo $HELM
#      fi

  done

#Define time
#time=0
#if [[ "$#" = "2" ]]; then
#        time=$2
#fi


get_describe_info() {
    #echo "---------------------------------------"
    echo "##################################-Getting resources describe info-"
    #echo "---------------------------------------"
    #echo "---------------------------------------"
    namespace=$1
    log_base_dir=$2
    log_base_path=$3
    des_dir=${log_base_path}/describe
    mkdir ${des_dir}
    for attr in statefulsets internalCertificates crd deployments services replicasets endpoints daemonsets persistentvolumeclaims configmap pods nodes jobs persistentvolumes rolebindings roles secrets serviceaccounts storageclasses ingresses
        do
            dir=`echo $attr | tr '[:lower:]' '[:upper:]'`
            mkdir ${des_dir}/$dir
        done

    for attr in statefulsets internalCertificates crd deployments services replicasets endpoints daemonsets persistentvolumeclaims configmap pods nodes jobs persistentvolumes rolebindings roles secrets serviceaccounts storageclasses ingresses
        do
            dir=`echo $attr | tr '[:lower:]' '[:upper:]'`
            mkdir ${des_dir}/$dir
            kubectl --namespace ${namespace} get $attr > ${des_dir}/$dir/$attr.txt
            echo "Getting describe information on $dir.."
            for i in `kubectl --namespace ${namespace} get $attr | grep -v NAME | awk '{print $1}'`
                do
                    kubectl --namespace ${namespace}  describe  $attr  $i > ${des_dir}/$dir/$i.yaml &
                    while true
                    do
                    cmd_count=$(ps -ef |grep kubectl|grep -v 'grep'|wc -l)
                    if [ $cmd_count -ge $max_cmd ]
                    then
                    sleep 3
                    else
                    break
                    fi
                    done
                done
        done
}
get_events() {
    echo "####################################-Getting list of events -"
    namespace=$1
    log_base_dir=$2
    log_base_path=$3
    echo "##############################################get_events"$namespace
    event_dir=$log_base_path/describe/EVENTS
    mkdir -p $event_dir

    kubectl --namespace ${namespace} get events > $event_dir/events.txt  &
}
get_pods_logs() {
    #echo "---------------------------------------"
    echo "###################################-Getting logs per POD-"
    #echo "---------------------------------------"
    #echo "---------------------------------------"

    namespace=$1
    log_base_dir=$2
    log_base_path=$3
    echo "##############################################get_pods_logs"$namespace
    logs_dir=${log_base_path}/logs
    mkdir ${logs_dir}
    mkdir ${logs_dir}/env
    kubectl --namespace ${namespace} get pods > ${logs_dir}/kube_podstolog.txt
    for i in `kubectl --namespace ${namespace} get pods | grep -v NAME | awk '{print $1}'`
        do
            pod_status=$(kubectl --namespace ${namespace} get pod $i -o jsonpath='{.status.phase}')
            index=0
            for j in `kubectl --namespace ${namespace} get pod $i -o jsonpath='{.spec.containers[*].name}'`
                do
                    kubectl --namespace ${namespace} logs $i -c $j --since=$time> ${logs_dir}/${i}_${j}.txt &
                    restartcount=$(kubectl --namespace ${namespace} get pod $i -o jsonpath='{.status.containerStatuses['$index'].restartCount}')
                    if [ $restartcount != 0 ]; then
                        kubectl --namespace ${namespace} logs $i -c $j -p > ${logs_dir}/${i}_${j}_prev.txt &2>/dev/null
                    fi
                    # Only exec Pod in Running state
                    if [[ "$pod_status" == "Running" ]]; then
                        kubectl --namespace ${namespace} exec  $i -c $j -- env > ${logs_dir}/env/${i}_${j}_env.txt &
                    fi
                    ((index++))

                    while true
                    do
                    cmd_count=$(ps -ef |grep kubectl|grep -v 'grep'|wc -l)
                    if [ $cmd_count -ge $max_cmd ]
                    then
                    sleep 3
                    else
                    break
                    fi
                    done

                done
            init_containers=$(kubectl --namespace ${namespace} get pod $i -o jsonpath='{.spec.initContainers[*].name}')
            index=0
            for j in $init_containers
                do
                    kubectl --namespace ${namespace} logs $i -c $j --since=$time> ${logs_dir}/${i}_${j}.txt
                    restartcount=$(kubectl --namespace ${namespace} get pod $i -o jsonpath='{.status.initContainerStatuses['$index'].restartCount}')
                    if [ $restartcount != 0 ]; then
                        kubectl --namespace ${namespace} logs $i -c $j -p > ${logs_dir}/${i}_${j}_prev.txt &2>/dev/null
                    fi
                    ((index++))
                done
        done
}

get_helm_info() {
    #echo "-----------------------------------------"
    echo "-Getting Helm Charts for the deployments-"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"
    namespace=$1
    log_base_dir=$2
    log_base_path=$3
    echo "##############################################get_helm_info"$namespace


    helm_dir=${log_base_path}/helm
    mkdir ${helm_dir}
    helm --namespace ${namespace} list > ${helm_dir}/helm_deployments.txt

    for i in `helm --namespace ${namespace} list| grep -v NAME | awk '{print $1}'`
        do
            #echo $i
            #helm get $i > ${helm_dir}/$i.txt
            #$HELM $i --namespace ${namespace}> ${helm_dir}/$i.txt
            $HELM $i > ${helm_dir}/$i.txt
            echo $HELM $i
        done
}


cmm_log() {

    #echo "-----------------------------------------"
    echo "-Verifying for CM logs -"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"
    namespace=$1
    log_base_dir=$2
    log_base_path=$3
    echo "##############################################get_cmm_logs"$namespace


    cmm_log_dir=${log_base_path}/logs/cmm_log

    if (kubectl --namespace=${namespace} get pods | grep -i cm-med|grep Running)
      then
        mkdir ${cmm_log_dir}
        echo "CM Pods found running, gathering cmm_logs.."
          for i in `kubectl --namespace=${namespace} get pods | grep -i cm-med | awk '{print $1}'`
            do
               echo $i
              kubectl --namespace ${namespace} exec $i --  collect_logs > ${cmm_log_dir}/cmmlog_$i.tgz
            done
            #Checking for schemas and configurations
            POD_NAME=`kubectl --namespace ${namespace} get pods |grep cm-mediator|grep -vi notifier|head -1|awk '{print $1}'`
            kubectl --namespace ${namespace} exec $POD_NAME -- curl -X GET http://localhost:5003/cm/api/v1/schemas | json_pp > ${cmm_log_dir}/schemas.json
            kubectl --namespace ${namespace} exec $POD_NAME -- curl -X GET http://localhost:5003/cm/api/v1/configurations | json_pp >  ${cmm_log_dir}/configurations.json
            configurations_list=$(cat ${cmm_log_dir}/configurations.json | grep \"name\" | cut -d : -f 2 | tr -d \",)
            for i in $configurations_list
            do
                    kubectl --namespace ${namespace} exec $POD_NAME -- curl -X GET http://localhost:5003/cm/api/v1/configurations/$i|json_pp > ${cmm_log_dir}/config_$i.json
            done
    else
         echo "CM Containers not found or not running, doing nothing"
    fi
}

siptls_logs() {

    #echo "-----------------------------------------"
    echo "-Verifying for SIP-TLS logs -"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"
    namespace=$1
    log_base_dir=$2
    log_base_path=$3

    echo "##############################################siptls__logs"$namespace


    siptls_log_dir=${log_base_path}/logs/sip_kms_dced

    if (kubectl --namespace=${namespace} get pods | grep -i sip-tls)
      then
      mkdir ${siptls_log_dir}
        echo "SIP-TLS Pods found, gathering siptls_logs.."
          for i in `kubectl --namespace=${namespace} get pods | grep -i sip-tls | awk '{print $1}'`
            do
               echo $i
              kubectl --namespace ${namespace} exec $i -- /bin/bash /sip-tls/sip-tls-alive.sh && echo $? > ${siptls_log_dir}/alive_log_$i.out
              kubectl --namespace ${namespace} exec $i -- /bin/bash /sip-tls/sip-tls-ready.sh && echo $? > ${siptls_log_dir}/ready_log_$i.out
              kubectl logs --namespace ${namespace}  $i sip-tls > ${siptls_log_dir}/sip-tls_log__$i.out
              kubectl logs --namespace ${namespace}  $i sip-tls --previous > ${siptls_log_dir}/sip-tls-previous_log_$i.out
              kubectl --namespace ${namespace} exec $i -- env > ${siptls_log_dir}/env_log__$i.out
            done

            kubectl --namespace ${namespace} exec eric-sec-key-management-main-0 -c kms -- bash -c 'vault status -tls-skip-verify' > ${siptls_log_dir}/vault_status_kms.out
            kubectl --namespace ${namespace} exec eric-sec-key-management-main-0 -c shelter -- bash -c 'vault status -tls-skip-verify' > ${siptls_log_dir}/vault_status_shelter.out
            kubectl get crd --namespace ${namespace}  servercertificates.com.ericsson.sec.tls -o yaml  > ${siptls_log_dir}/servercertificates_crd.yaml
            kubectl get  --namespace ${namespace}  servercertificates -o yaml  > ${siptls_log_dir}/servercertificates.yaml
            kubectl get crd --namespace ${namespace}  clientcertificates.com.ericsson.sec.tls -o yaml  > ${siptls_log_dir}/clientcertificates_crd.yaml
            kubectl get  --namespace ${namespace}  clientcertificates -o yaml  > ${siptls_log_dir}/clientcertificates.out
            kubectl get crd --namespace ${namespace} certificateauthorities.com.ericsson.sec.tls -o yaml  > ${siptls_log_dir}/certificateauthorities_crd.yaml
            kubectl get  --namespace ${namespace}  certificateauthorities -o yaml  > ${siptls_log_dir}/certificateauthorities.out
            kubectl get  --namespace ${namespace}  internalcertificates.siptls.sec.ericsson.com  -o yaml  > ${siptls_log_dir}/internalcertificates.yaml
            kubectl get  --namespace ${namespace}  internalusercas.siptls.sec.ericsson.com  -o yaml  > ${siptls_log_dir}/internalusercas.yaml
            kubectl get secret --namespace ${namespace} -l com.ericsson.sec.tls/created-by=eric-sec-sip-tls > ${siptls_log_dir}/secrets_created_by_eric_sip.out
            pod_name=$(kubectl get po -n ${namespace} -l app=eric-sec-key-management -o jsonpath="{.items[0].metadata.name}")
            kubectl --namespace ${namespace} exec $pod_name -c kms -- env VAULT_SKIP_VERIFY=true vault status > ${siptls_log_dir}/kms_status_.out

    else
         echo "SIP-TLS Containers not found or not running, doing nothing"
    fi
}
cmy_log() {

    #echo "-----------------------------------------"
    echo "-Verifying for CM Yang logs -"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"

    cmy_log_dir=${log_base_path}/logs/sssd_cmy_log

    if (kubectl --namespace=${namespace} get pods | grep -i yang|grep Running)
      then
        mkdir ${cmy_log_dir}
        echo "CM Yang Pods found running, gathering cmyang_logs.."
          for i in `kubectl --namespace=${namespace} get pods | grep -i yang | awk '{print $1}'`
            do
               echo $i
#              kubectl --namespace ${namespace} logs $i confd -p  > ${cmy_log_dir}/confd_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i notification-sender -p  > ${cmy_log_dir}/notification-sender_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i yang-ext -p  > ${cmy_log_dir}/yang-ext_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i cpa -p  > ${cmy_log_dir}/cpa_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i ypint -p  > ${cmy_log_dir}/ypint_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i sshd -p  > ${cmy_log_dir}/sshd_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i ss -p  > ${cmy_log_dir}/ss_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i init-db -p  > ${cmy_log_dir}/init-db_previous_$i.txt
#              kubectl --namespace ${namespace} logs $i confd   > ${cmy_log_dir}/confd_$i.txt
#              kubectl --namespace ${namespace} logs $i notification-sender   > ${cmy_log_dir}/notification-sender_$i.txt
#              kubectl --namespace ${namespace} logs $i yang-ext   > ${cmy_log_dir}/yang-ext_$i.txt
#              kubectl --namespace ${namespace} logs $i cpa   > ${cmy_log_dir}/cpa_$i.txt
#              kubectl --namespace ${namespace} logs $i ypint   > ${cmy_log_dir}/ypint_$i.txt
#              kubectl --namespace ${namespace} logs $i sshd   > ${cmy_log_dir}/sshd_$i.txt
#              kubectl --namespace ${namespace} logs $i ss   > ${cmy_log_dir}/ss_$i.txt
#              kubectl --namespace ${namespace} logs $i init-db   > ${cmy_log_dir}/init-db_$i.txt
              mkdir ${cmy_log_dir}/sssd_$i/
              kubectl --namespace ${namespace} cp $i:/var/log/sssd   ${cmy_log_dir}/ssd_$i/ -c sshd
            done

    else
         echo "CM Yang Containers not found or not running, doing nothing"
    fi
}
basic_checks () {
    namespace=$1
    log_base_dir=$2
    log_base_path=$3

    mkdir  ${log_base_path}/logs/err
    mkdir  ${log_base_path}/logs/SE
#    for i in `ls ${log_base_path}/logs/`
#    do
#            filename=`echo $i| awk '{print substr($1,1,length($1)-4)}'`
#            cat ${log_base_path}/logs/$i | egrep -i "err|warn|crit" > ${log_base_path}/logs/err/$filename.err.txt
#    done
     for i in `ls ${log_base_path}/logs/`
      do
             filename=`echo $i| awk '{print substr($1,1,length($1)-4)}'`
             log_path="${log_base_path}/logs/$i"
      if ! [ -d $log_path ]; then
             cat ${log_path} | egrep -i "err|warn|crit" > ${log_base_path}/logs/err/$filename.err.txt
      fi
    done
    #cd ${log_base_path}/describe/PODS
    for i in `ls ${log_base_path}/describe/PODS`
    do
            version=`cat ${log_base_path}/describe/PODS/$i |grep "app.kubernetes.io/version"`
           echo $i $version >>${log_base_path}/describe/PODS/pods_image_versions.txt
   done
   esRest="kubectl -n ${namespace} exec -c searchengine $(kubectl get pods -n ${namespace} -l "app=eric-data-search-engine,role in (ingest-tls,ingest)" -o jsonpath="{.items[0].metadata.name}") -- /bin/esRest"
   $esRest GET /_cat/nodes?v>${log_base_path}/logs/SE/nodes.txt
   $esRest GET /_cat/indices?v>${log_base_path}/logs/SE/indices.txt
   $esRest GET /_cluster/health?pretty > ${log_base_path}/logs/SE/health.txt
   $esRest GET /_cluster/allocation/explain?pretty > ${log_base_path}/logs/SE/allocation.txt
  }
compress_files() {
    namespace=$1
    log_base_dir=$2
    log_base_path=$3

    echo "Generating tar file and removing logs directory..."
    tar cfz $PWD/${log_base_dir}.tgz ${log_base_dir}
    echo  -e "\e[1m\e[31mGenerated file $PWD/${log_base_dir}.tgz, Please collect and send to ADP Support!\e[0m"
    rm -r $PWD/${log_base_dir}
}

#namespaces=$*

for namespace in $namespaces;do
log_base_dir=logs_${namespace}_$(date "+%Y-%m-%d-%H-%M-%S")
log_base_path=$PWD/${log_base_dir}
mkdir ${log_base_dir}
      helm version | head -1 >$log_base_path/helm_version.txt
      if eval ' grep v3 $log_base_path/helm_version.txt'
        then
        echo "HELM 3 identified"
        HELM='helm get all --namespace='${namespace}
   #    echo $HELM
      else
        HELM='helm get --namespace='${namespace}
       echo $HELM
      fi

get_describe_info $namespace $log_base_dir $log_base_path &
get_events $namespace $log_base_dir $log_base_path &
get_pods_logs $namespace $log_base_dir $log_base_path  &
get_helm_info   $namespace $log_base_dir $log_base_path  &
cmm_log   $namespace $log_base_dir $log_base_path  &
siptls_logs  $namespace $log_base_dir $log_base_path   &
echo "$namespace $log_base_dir $log_base_path" >> $tmp_file
#cmy_log
#wait
#basic_checks   $namespace $log_base_dir $log_base_path  &
#wait
#compress_files  &
done
while read  line
do
  basic_checks   $line &
  wait
  compress_files $line &
  wait
done  < $tmp_file
