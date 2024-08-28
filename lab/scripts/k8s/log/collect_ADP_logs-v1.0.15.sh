#!/bin/bash

############################################################################
# organization "Ericsson AB";                                              #
# contact " ADP Support via mail";                                         #
# description "Script to collect ADP logs for Support.                     #
#        Copyright (c) 2020 Ericsson AB. All rights reserved.";            #
############################################################################
# Author: EPRGGGZ Gustavo Garcia G.                                        #
# 1.0.15                                                                   #
# Script to collect logfiles for Kubernetes Cluster based on Spider input  #
# The script wil also collect HELM charts configuration                    #
# To use, execute collect_ADP_logs.sh <namespace>  <opt_min_to_collect>    #
#                                                                          #
############################################################################

############################################################################
#                          History                                         #
# 2023-06-06 XKHADOA    Version 1.0.15                                     #
#                       Replaced exit by return in cmyp_yang_schemas       #
#                                                                          # 
# 2023-06-06 XKHADOA    Version 1.0.14                                     #
#                       Changed the logic to detect the CM pod and DB      #
#                                                                          # 
#                                                                          #
# 2023-02-10 XTSXSJL    Version 1.0.13                                     #
#                       Change overload protection to use jobs             #
#                       Changed path for CMM cert file                     #
#                       Defined dced container when collecting DECD info   #  
# 2022-10-18 EPRGGGZ    Version 1.0.12                                     #
#                       Fixing bug on CMM and CMY schema collection        #
# 2022-10-18 EHEIKOM    Introducing variables for version and operation    #
#                       handling                                           #
# 2022-10-05 EPRGGGZ    Version 1.0.10                                     #
#                       Fixing bug on the cmy schema recollection          #
# 2022-08-30 EPRGGGZ    Version 1.0.9                                      #
#                       Enabling the cmy schema recollection               #
#                       Adding certificates to curl for cm                 #
# 2022-05-18 EPRGGGZ    Version 1.0.8                                      #
#                       Changing logic for applications which do not use   #
#                       Default names for KVDB                             #
#                       Adding logic when finding multiple DDBPG.          #
#                       Adding function SM as contribution from Service    #
#                       Mesh (ECALNOU)                                     #
# 2022-02-22 EPRGGGZ    Version 1.0.7                                      #
#                       Organizing describe directory,limiting KVDB stat   #
# 2022-02-15 EPRGGGZ    Version 1.0.6                                      #
#                       fixing problem with diameter function              #
# 2022-01-08 EPRGGGZ    Version 1.0.5                                      #
#                       Adding cluster parameters lost for an update       #
# 2021-12-28 EPRGGGZ    Version 1.0.4                                      #
#                       Enabling previous model recolection for CMYP       #
# 2021-12-28 EPRGGGZ    Version 1.0.3                                      #
#                       Adding SS7 collect information function            #
#                       Adding parallel collection (10 items)              #
#                       Adding describe of all objects on namespace        #
#                       Fixing problems with KVDB log collection           #
#                       Adding -o wide option                              #
#                       Adding top node and top pod                        #
#                                                                          #
# 2021-12-28 EYANPHE    Version 1.0.2                                      #
#                       Collect YANG and JSON schemas using script         #
#                                                                          #
# 2021-10-14 EYANPHE    Version 1.0.1                                      #
#                       Also collect YANG schemas and JSON schemas         #
#                                                                          #
# 2021-08-06 EPRGGGZ    Version 1.0.0                                      #
#                       Improved logic to only gather prev logs if restart #
#                       Added DCED printouts under sip_kms_dced/DCED       #
#                       Added KVDBAG printouts on KVDBAG                   #
#                       Added script version on scriptversion.txt          #
#                       Added grep for disk and latency errors  under err  #
#                                                                          #
# 2021-04-09 XKHADOA    Collect dumpState, dumpConfig and Transport Dia    #
#                                                                          #
# 2021-03-26 EPRGGGZ    Enabled collection of ssd one more time for cmyp   #
#                                                                          #
# 2021-03-26 XKHADOA    Added Removed restart count check                  #
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


namespace=$1

# Validate namespace
kubectl get namespace "$namespace" &>/dev/null

if [ $? != 0 ]; then
  echo "ERROR: The namespace $namespace does not exist. You can use \"kubectl get namespace\" command to verify your namespace"
  echo -e $USAGE
  exit 1
fi

#Define time
time=0
if [[ "$#" = "2" ]]; then
        time=$2
fi

# Define variables for version and operation handling
# 1. Version of the script
Version="1.0.15"

# 2. Number of parallel heavier describe operations
heavyOper=15

# 3. Number of parallel lighter describe operations
lightOper=20

# 4. Delay between the waves of operations
waitTime=0.5

#Create a directory for placing the logs
log_base_dir=logs_"${namespace}"_$(date "+%Y-%m-%d-%H-%M-%S")
log_base_path=$PWD/"${log_base_dir}"
mkdir "${log_base_dir}"
#Check if there is helm2  or helm3 deployment

echo "Collect script $Version" > $log_base_path/script_version.txt
helm version | head -1 >$log_base_path/helm_version.txt
if eval ' grep v3 $log_base_path/helm_version.txt'
then
        echo "HELM 3 identified"
        HELM='helm get all --namespace='"${namespace}"
   #    echo $HELM
else
        HELM='helm get --namespace='"${namespace}"
       echo $HELM
fi

get_describe_info() {
    #echo "---------------------------------------"
    echo "-Getting resources describe info-"
    #echo "---------------------------------------"
    #echo "---------------------------------------"

    des_dir="${log_base_path}"/describe
    mkdir -p ${des_dir}/OTHER
    counter=0
    for attr in statefulsets internalCertificates crd deployments services replicasets endpoints daemonsets persistentvolumeclaims configmap pods nodes jobs persistentvolumes rolebindings roles secrets serviceaccounts storageclasses ingresses httpproxy
    #for attr in $( kubectl api-resources --verbs=list --namespaced --no-headers |grep -v events| sed 's/true/;/g'| awk -F\; '{print $2}'|sort -u) crd storageclasses persistentvolumes  nodes 
        do
            dir=`echo $attr | tr '[:lower:]' '[:upper:]'`
            mkdir ${des_dir}/$dir
            kubectl --namespace "${namespace}" get $attr  -o wide> ${des_dir}/$dir/$attr.txt
            echo "Getting describe information on $dir.."
            for i in `kubectl --namespace "${namespace}" get $attr | grep -v NAME | awk '{print $1}'`
                do
                    kubectl --namespace "${namespace}"  describe  $attr  $i > ${des_dir}/$dir/$i.yaml &
                    while [ $(jobs -r | wc -l) -ge $heavyOper ] ;
                      do
                        sleep $waitTime ;
                    done
                done
        done
    #for attr in statefulsets internalCertificates crd deployments services replicasets endpoints daemonsets persistentvolumeclaims configmap pods nodes jobs persistentvolumes rolebindings roles secrets serviceaccounts storageclasses ingresses httpproxy
    for attr in $( kubectl api-resources --verbs=list --namespaced --no-headers |egrep -vi "events|statefulsets|internalCertificates|crd|deployments|services|replicasets|endpoints|daemonsets|persistentvolumeclaims|configmap|pod|nodes|jobs|persistentvolumes|rolebindings|roles|secrets|serviceaccounts|storageclasses|ingresses|httpproxy"| sed 's/true/;/g'| awk -F\; '{print $2}'|sort -u)  
        do
            dir=`echo $attr | tr '[:lower:]' '[:upper:]'`
            mkdir ${des_dir}/OTHER/$dir
            kubectl --namespace "${namespace}" get $attr  -o wide> ${des_dir}/OTHER/$dir/$attr.txt
            echo "Getting describe information on $dir.."
            for i in `kubectl --namespace "${namespace}" get $attr | grep -v NAME | awk '{print $1}'`
                do
                    kubectl --namespace "${namespace}"  describe  $attr  $i > ${des_dir}/OTHER/$dir/$i.yaml &
                    while [ $(jobs -r | wc -l) -ge $lightOper ] ;
                      do
                        sleep $waitTime ;
                    done
                done
        done
}
get_events() {
    echo "-Getting list of events -"
    event_dir=$log_base_path/describe/EVENTS
    mkdir -p $event_dir

    kubectl --namespace "${namespace}" get events > $event_dir/events.txt
}
get_pods_logs() {
    #echo "---------------------------------------"
    echo "-Getting logs per POD-"
    #echo "---------------------------------------"
    #echo "---------------------------------------"

    logs_dir="${log_base_path}"/logs
    mkdir ${logs_dir}
    mkdir ${logs_dir}/env
    counter=0
    kubectl --namespace "${namespace}" get pods -o wide > ${logs_dir}/kube_podstolog.txt
    for i in `kubectl --namespace "${namespace}" get pods | grep -v NAME | awk '{print $1}'`
        do
            pod_status=$(kubectl --namespace "${namespace}" get pod $i -o jsonpath='{.status.phase}')
            pod_restarts=$(kubectl --namespace "${namespace}" get pod $i |grep -vi restarts|awk '{print $4}')
            for j in `kubectl --namespace "${namespace}" get pod $i -o jsonpath='{.spec.containers[*].name}'`
                do
                    kubectl --namespace "${namespace}" logs $i -c $j --since=$time> ${logs_dir}/${i}_${j}.txt &

                    if [[ "$pod_restarts" > "0" ]]; then
                    kubectl --namespace "${namespace}" logs $i -c $j -p > ${logs_dir}/${i}_${j}_prev.txt 2>/dev/null &
                    fi
                    # Only exec Pod in Running state
                    if [[ "$pod_status" == "Running" ]]; then
                        kubectl --namespace "${namespace}" exec  $i -c $j -- env > ${logs_dir}/env/${i}_${j}_env.txt &
                    fi
                done
                while [ $(jobs -r | wc -l) -ge $lightOper ] ;
                  do
                    sleep $waitTime ;
                  done

            init_containers=$(kubectl --namespace "${namespace}" get pod $i -o jsonpath='{.spec.initContainers[*].name}')
            for j in $init_containers
                do
                    kubectl --namespace "${namespace}" logs $i -c $j --since=$time> ${logs_dir}/${i}_${j}.txt

                    if [[ "$pod_restarts" > "0" ]]; then
                    kubectl --namespace "${namespace}" logs $i -c $j -p > ${logs_dir}/${i}_${j}_prev.txt 2>/dev/null
                    fi
                done
        done
}

get_helm_info() {
    #echo "-----------------------------------------"
    echo "-Getting Helm Charts for the deployments-"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"

    helm_dir="${log_base_path}"/helm
    mkdir ${helm_dir}
    helm --namespace "${namespace}" list > ${helm_dir}/helm_deployments.txt

    for i in `helm --namespace "${namespace}" list| grep -v NAME | awk '{print $1}'`
        do
            #echo $i
            #helm get $i > ${helm_dir}/$i.txt
            #$HELM $i --namespace "${namespace}"> ${helm_dir}/$i.txt
            $HELM $i > ${helm_dir}/$i.txt
            echo $HELM $i
        done
}


cmm_log() {

    #echo "-----------------------------------------"
    echo "-Verifying for CM logs -"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"
    cmm_log_dir="${log_base_path}"/logs/cmm_log
    if (kubectl --namespace="${namespace}" get pods | grep -i cm-med|grep Running)
      then
        mkdir ${cmm_log_dir}
        echo "CM Pods found running, gathering cmm_logs.."
          for i in `kubectl --namespace="${namespace}" get pods | grep -i cm-med | awk '{print $1}'`
            do
               echo $i
              kubectl --namespace "${namespace}" exec $i --  collect_logs > ${cmm_log_dir}/cmmlog_$i.tgz
            done
            #Checking for schemas and configurations
            POD_NAME=`kubectl --namespace "${namespace}" get pods |grep cm-mediator|grep -vi notifier|head -1|awk '{print $1}'`
            # handle no HTTPS support in cmm
            CURL_BASE_URL="https://localhost:5004"
            CURL_OPTS="--cacert /etc/sip-tls-ca/cacertbundle.pem --cert /etc/sip-tls-client/clicert.pem --key /etc/sip-tls-client/cliprivkey.pem"
            kubectl --namespace "${namespace}" exec $POD_NAME -- ls /etc/sip-tls-ca/cacertbundle.pem
            if [[ $? != 0 ]]
            then
                CURL_BASE_URL="http://eric-cm-mediator:5003"
                CURL_OPTS=""
            fi
            kubectl --namespace "${namespace}" exec $POD_NAME -- curl -X GET ${CURL_OPTS} "${CURL_BASE_URL}/cm/api/v1/schemas" | json_pp > ${cmm_log_dir}/schemas.json
            kubectl --namespace "${namespace}" exec $POD_NAME -- curl -X GET ${CURL_OPTS} "${CURL_BASE_URL}/cm/api/v1/configurations" | json_pp > ${cmm_log_dir}/configurations.json
            configurations_list=$(cat ${cmm_log_dir}/configurations.json | grep \"name\" | cut -d : -f 2 | tr -d \",)
            for i in $configurations_list
            do
                 kubectl --namespace "${namespace}" exec $POD_NAME -- curl -X GET ${CURL_OPTS} "${CURL_BASE_URL}/cm/api/v1/configurations/${i}" | json_pp > ${cmm_log_dir}/config_$i.json
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

    siptls_log_dir="${log_base_path}"/logs/sip_kms_dced

    if (kubectl --namespace="${namespace}" get pods | grep -i sip-tls)
      then
      mkdir ${siptls_log_dir}
        echo "SIP-TLS Pods found, gathering siptls_logs.."
          for i in `kubectl --namespace="${namespace}" get pods | grep -i sip-tls | awk '{print $1}'`
            do
               echo $i
              kubectl --namespace "${namespace}" exec $i -c sip-tls  -- /bin/bash /sip-tls/sip-tls-liveness.sh && echo $? > ${siptls_log_dir}/alive_log_$i.out
              kubectl --namespace "${namespace}" exec $i -c sip-tls  -- /bin/bash /sip-tls/sip-tls-readiness.sh && echo $? > ${siptls_log_dir}/ready_log_$i.out
              kubectl logs --namespace "${namespace}"  $i sip-tls  > ${siptls_log_dir}/sip-tls_log_$i.out
              kubectl logs --namespace "${namespace}"  $i sip-tls   --previous > ${siptls_log_dir}/sip-tls-previous_log_$i.out 2>/dev/null
              kubectl --namespace "${namespace}" exec $i  -c sip-tls -- env > ${siptls_log_dir}/env_log_$i.out
            done

            kubectl --namespace "${namespace}" exec eric-sec-key-management-main-0 -c kms -- bash  -c 'vault status -tls-skip-verify' > ${siptls_log_dir}/vault_status_kms.out
            kubectl --namespace "${namespace}" exec eric-sec-key-management-main-0 -c shelter -- bash -c  'vault status -tls-skip-verify' > ${siptls_log_dir}/vault_status_shelter.out
            kubectl get crd --namespace "${namespace}"  servercertificates.com.ericsson.sec.tls -o yaml  > ${siptls_log_dir}/servercertificates_crd.yaml
            kubectl get  --namespace "${namespace}"  servercertificates -o yaml  > ${siptls_log_dir}/servercertificates.yaml
            kubectl get crd --namespace "${namespace}"  clientcertificates.com.ericsson.sec.tls -o yaml  > ${siptls_log_dir}/clientcertificates_crd.yaml
            kubectl get  --namespace "${namespace}"  clientcertificates -o yaml  > ${siptls_log_dir}/clientcertificates.out
            kubectl get crd --namespace "${namespace}" certificateauthorities.com.ericsson.sec.tls -o yaml  > ${siptls_log_dir}/certificateauthorities_crd.yaml
            kubectl get  --namespace "${namespace}"  certificateauthorities -o yaml  > ${siptls_log_dir}/certificateauthorities.out
            kubectl get  --namespace "${namespace}"  internalcertificates.siptls.sec.ericsson.com  -o yaml  > ${siptls_log_dir}/internalcertificates.yaml
            kubectl get  --namespace "${namespace}"  internalusercas.siptls.sec.ericsson.com  -o yaml  > ${siptls_log_dir}/internalusercas.yaml
            kubectl get secret --namespace "${namespace}" -l com.ericsson.sec.tls/created-by=eric-sec-sip-tls > ${siptls_log_dir}/secrets_created_by_eric_sip.out
            pod_name=$(kubectl get po -n "${namespace}" -l app=eric-sec-key-management -o jsonpath="{.items[0].metadata.name}")
            kubectl --namespace "${namespace}" exec $pod_name -c kms -- env VAULT_SKIP_VERIFY=true vault status > ${siptls_log_dir}/kms_status_.out

            if (kubectl --namespace="${namespace}" get pods | grep -i eric-sec-key-management-main-1)
            then

            echo "Gathering information to check split brain on KMS"

           mkdir ${siptls_log_dir}/KMS_splitbrain_check
           kmsspbr=${siptls_log_dir}/KMS_splitbrain_check
           kubectl exec --namespace "${namespace}" eric-sec-key-management-main-0 -c kms -- bash -c "date;export VAULT_ADDR=http://localhost:8202;echo 'KMS-0';vault status -tls-skip-verify|grep 'HA Enabled' -A3" > ${kmsspbr}/vault_Stat_HA.log
kubectl exec --namespace "${namespace}" eric-sec-key-management-main-1 -c kms -- bash -c "export VAULT_ADDR=http://localhost:8202;echo 'KMS-1';vault status -tls-skip-verify|grep 'HA Enabled' -A3" >> ${kmsspbr}/vault_Stat_HA.log
kubectl exec --namespace "${namespace}" eric-sec-key-management-main-0 -c shelter -- bash -c "export VAULT_ADDR=http://localhost:8212;echo 'SHELTER-0';vault status -tls-skip-verify|grep 'HA Enabled' -A3" >> ${kmsspbr}/vault_Stat_HA.log
kubectl exec --namespace "${namespace}" eric-sec-key-management-main-1 -c shelter -- bash -c "export VAULT_ADDR=http://localhost:8212;echo 'SHELTER-1';vault status -tls-skip-verify|grep 'HA Enabled' -A3" >> ${kmsspbr}/vault_Stat_HA.log

kubectl logs --namespace "${namespace}" eric-sec-key-management-main-0 -c kms | grep -e "active operation" -e "standby mode">> ${kmsspbr}/active_operation.log
kubectl logs --namespace "${namespace}" eric-sec-key-management-main-1 -c kms | grep -e "active operation" -e "standby mode">> ${kmsspbr}/active_operation.log
kubectl logs --namespace "${namespace}" eric-sec-key-management-main-0 -c shelter | grep -e "active operation" -e "standby mode">> ${kmsspbr}/active_operation.log
kubectl logs --namespace "${namespace}" eric-sec-key-management-main-1 -c shelter | grep -e "active operation" -e "standby mode">> ${kmsspbr}/active_operation.log
fi

    else
         echo "SIP-TLS Containers not found or not running, doing nothing"
    fi
}
cmy_log() {
    #echo "-----------------------------------------"
    echo "-Verifying for CM Yang logs -"
    #echo "-----------------------------------------"

    cmy_log_dir="${log_base_path}"/logs/cmy_log

    if (kubectl --namespace="${namespace}" get pods | grep -i yang|grep Running)
    then
        mkdir -p ${cmy_log_dir}
        echo "CM Yang Pods found running, gathering cmyang_logs.."
        for i in `kubectl --namespace="${namespace}" get pods | grep -i yang | awk '{print $1}'`
        do
            echo $i
            mkdir ${cmy_log_dir}/sssd_$i/
            kubectl --namespace "${namespace}" cp $i:/var/log/sssd   ${cmy_log_dir}/sssd_$i/ -c sshd
        done
    else
        echo "CM Yang Containers not found or not running, doing nothing"
    fi

    cmyp_yang_schemas ${cmy_log_dir} "${namespace}"
    cmyp_json_schemas ${cmy_log_dir} "${namespace}"
}

cmyp_json_schemas() {
    #echo "-----------------------------------------"
    echo "-Collect JSON schemas-"
    #echo "-----------------------------------------"

    cmy_log_dir=$1
    namespace=$2
    # We can use postgres user or get from environment CM_BACKEND_USERNAME variable
    CMM_POD=`kubectl get pod -n "${namespace}" -l app=eric-cm-mediator -o name | head -n 1`
    ddb_backend=`kubectl describe $CMM_POD -n "${namespace}" | grep CM_BACKEND_SERVER | head -n 1`
    dbname=$(echo $ddb_backend | sed 's/.*dbname=//; s/ user.*//')
    ddb_service=$(echo $ddb_backend | sed 's/.*host=//; s/ port.*//')
    # Main container is database containter so don't need to get container name
    ddb_pod=`kubectl get pod -n "${namespace}" -l app=$(kubectl describe svc $ddb_service -n "${namespace}" | grep app= | cut -d = -f2) | grep Running | head -n 1 | awk '{print $1}'`
    if [[ $ddb_pod != "" ]]; then
      echo "WARNING: No backend DB Running for CMM"
      return
    fi

    DDB_CMD="kubectl exec ${ddb_pod} -n "${namespace}" -- /bin/bash -c"
    JSON_PATH=$(mktemp -d -u "/tmp/jsonSchemas.XXXXXX")
    LOCAL_PATH=${cmy_log_dir}/schemas_${ddb_pod}/
    mkdir -p ${LOCAL_PATH}

    ${DDB_CMD} "if [ -d ${JSON_PATH} ]; then rm -rf ${JSON_PATH}; fi; mkdir ${JSON_PATH}"
    jsonNames=$(${DDB_CMD} "echo \"SELECT name FROM schemas\" | /usr/bin/psql --quiet --tuples-only -d ${dbname} -U postgres")
    for n in ${jsonNames}
    do
     echo fetch ${n}
     fetch="echo \"SELECT data->'schema' FROM schemas WHERE name='${n}'\" | /usr/bin/psql --quiet --tuples-only -d ${dbname} -U postgres > ${JSON_PATH}/${n}.json"
     ${DDB_CMD} "${fetch}"
     echo fetch ${n} done
    done

    ${DDB_CMD} "cd ${JSON_PATH} && tar -czf jsonSchemas.tar.gz *"
#    kubectl cp ${ddb}:${JSON_PATH}/jsonSchemas.tar.gz ${LOCAL_PATH}/jsonSchemas.tar.gz -n "${namespace}" -c eric-data-document-database-pg
    kubectl cp ${ddb_pod}:${JSON_PATH}/jsonSchemas.tar.gz ${LOCAL_PATH}/jsonSchemas.tar.gz -n "${namespace}"

    tar xzvf ${LOCAL_PATH}/jsonSchemas.tar.gz -C ${LOCAL_PATH}/
    rm -f ${LOCAL_PATH}/jsonSchemas.tar.gz
    ${DDB_CMD} "rm -rf ${JSON_PATH}"
}

cmyp_yang_schemas() {
    #echo "-----------------------------------------"
    echo "-Collect YANG schemas-"
    #echo "-----------------------------------------"

    cmy_log_dir=$1
    namespace=$2
    DBNAME=`cat "${log_base_path}"/describe/PODS/*cm-yang*|grep POSTGRES_DBNAME: | head -1 | awk '{print $2}'`
    ddb_service=`cat "${log_base_path}"/describe/PODS/*cm-yang*|grep POSTGRES_SERVICE_HOST: | head -1 | awk '{print $2}'`
    ddb=`kubectl get pod -n "${namespace}" -l app=$(kubectl describe svc $ddb_service -n "${namespace}" | grep app= | cut -d = -f2) | grep Running | head -n 1 | awk '{print $1}'`
    if [[ $ddb == "" ]]; then
      echo "WARNING: No backend DB Running for CMYP"
      return
    fi
    # Main container is database containter so don't need to get container name.
    # We can hardcode to use eric-data-document-database-pg container name as it should not be changed event POD name is changed
    DDB_CMD="kubectl exec ${ddb} -n "${namespace}" -- /bin/bash -c"
    YANG_PATH=$(mktemp -d -u "/tmp/yangSchemas.XXXXXX")
    LOCAL_PATH=${cmy_log_dir}/schemas_${ddb}/
    mkdir -p ${LOCAL_PATH}

    #yangNames=`${DDB_CMD} "echo \"SELECT name FROM yangschemas\" | /usr/bin/psql --quiet --tuples-only -d adp_gs_cm -U postgres"`
    yangNames=`${DDB_CMD} "echo \"SELECT name FROM yangschemas\" | /usr/bin/psql --quiet --tuples-only -d ${DBNAME} -U postgres"`

    ${DDB_CMD} "if [ -d ${YANG_PATH} ]; then rm -rf ${YANG_PATH}; fi; mkdir ${YANG_PATH}"

    for n in ${yangNames}
    do
     echo fetch ${n}
     #fetch="echo \"SELECT data FROM yangschemas WHERE name='${n}'\" | /usr/bin/psql --quiet --tuples-only -d adp_gs_cm -U postgres > ${YANG_PATH}/${n}"
     fetch="echo \"SELECT data FROM yangschemas WHERE name='${n}'\" | /usr/bin/psql --quiet --tuples-only -d ${DBNAME} -U postgres > ${YANG_PATH}/${n}"
     ${DDB_CMD} "${fetch}"
     echo fetch ${n} done
    done

    ${DDB_CMD} "cd ${YANG_PATH} && tar -czf yangSchemas.tar.gz *"
    kubectl cp ${ddb}:${YANG_PATH}/yangSchemas.tar.gz ${LOCAL_PATH}/yangSchemas.tar.gz -n "${namespace}"

    tar xzvf ${LOCAL_PATH}/yangSchemas.tar.gz -C ${LOCAL_PATH}/
    rm -f ${LOCAL_PATH}/yangSchemas.tar.gz
    for f in ${LOCAL_PATH}/*
    do
     cat ${f} | `which xxd` -r -p > ${f}.tar.gz
     rm -f ${f}
    done

    ${DDB_CMD} "rm -rf ${YANG_PATH}"
}

function diameter_log (){
        if (kubectl --namespace="${namespace}" get pods | grep -i stm-diameter|grep Running)
      then
  DIA_POD=$(kubectl --namespace "${namespace}" get pod -l app=eric-stm-diameter -o name)
  pod_status=$(kubectl --namespace "${namespace}" get $DIA_POD -o jsonpath='{.status.phase}')
#  if [[ "$pod_status" == "Running" ]]; then
    diacc="${log_base_path}"/logs/dia/
    mkdir -p $diacc/pod
    for i in `kubectl --namespace "${namespace}" get pod -l app=eric-stm-diameter -o name`
    do 
    kubectl --namespace "$namespace" exec $i -- curl -s http://localhost:20100/dumpState > ${diacc}/${i}_dumpState.txt
    kubectl --namespace "$namespace" exec $i -- curl -s http://localhost:20100/troubleshoot/transportDump/v2 > ${diacc}/${i}_transport.txt
    kubectl --namespace "$namespace" exec $i -- curl -s http://localhost:20100/dumpConfig > ${diacc}/${i}_dumpConfig.txt
    done
#  fi
  fi
  }
#function osmn_log (){
#        if (kubectl --namespace="${namespace}" get pods | grep -i object-storage|grep Running)
#      then
#  OSMN_POD=$(kubectl --namespace "${namespace}" get pod -l app=eric-data-object-storage-mn -o name)
#  pod_status=$(kubectl --namespace "${namespace}" get $OSMN_POD -o jsonpath='{.status.phase}')
##  if [[ "$pod_status" == "Running" ]]; then
#    osmncc="${log_base_path}"/logs/osmn/
#    mkdir -p $osmncc/pod
#    for i in `kubectl --namespace "${namespace}" get pod -l app=eric-data-object-storage-mn  -o name`
#    do 
#       kubectl --namespace "$namespace" cp ${i}:/logs  > ${osmncc}/${i}_logs.txt
#       kubectl --namespace "$namespace" cp ${i}:/minio/tls_certs  > ${osmncc}/${i}_tls_certs.txt
#       kubectl --namespace "$namespace" cp ${i}:/kms-ca-certs > ${osmncc}/${i}_/kms-ca-certs.txt
#    done
#    for i in `kubectl --namespace "${namespace}" get pod -l app=eric-data-object-storage-mn-mgt  -o name`
#    do 
#       kubectl --namespace "$namespace" exec -it  ${i} - mc admin info --no-color client > ${osmncc}/${i}_admin_info.txt
#       kubectl --namespace "$namespace" exec -it  ${i} - mc admin  console --no-color client | tee osmn_console.txt > ${osmncc}/${i}_osmn_console.txt
#    done
##  fi
#  fi
#}
basic_checks () {
    mkdir  "${log_base_path}"/logs/err
    mkdir  "${log_base_path}"/logs/SE
     for i in `ls "${log_base_path}"/logs/`
      do
             filename=`echo $i| awk '{print substr($1,1,length($1)-4)}'`
             log_path=""${log_base_path}"/logs/$i"
      if ! [ -d $log_path ]; then
             cat "${log_path}" | egrep -i "err|warn|crit" > "${log_base_path}"/logs/err/$filename.err.txt
             cat "${log_path}" | egrep -i "failed to perform indices:data/write/bulk|latency|failed to send out heartbeat on time|disk|time out|timeout|timed out" > "${log_base_path}"/logs/err/$filename.latency.txt
      fi
    done
    #cd "${log_base_path}"/describe/PODS
    for i in `ls "${log_base_path}"/describe/PODS`
    do
            version=`cat "${log_base_path}"/describe/PODS/$i |grep "app.kubernetes.io/version"`
           echo $i $version >>"${log_base_path}"/describe/PODS/pods_image_versions.txt
   done
   kubectl --namespace "${namespace}" top pods > "${log_base_path}"/logs/top_pod_output.txt
   kubectl --namespace "${namespace}" top node > "${log_base_path}"/logs/top_node_output.txt


   #SE_POD=$(kubectl --namespace "${namespace}" get pod -l  "app=eric-data-search-engine,role in (ingest-tls,ingest)" -o jsonpath="{.items[0].metadata.name}")
  pod_status=$(kubectl --namespace "${namespace}" get  pods | grep search-engine|wc -l)
  if [[ "$pod_status" > "0" ]]; then
   esRest="kubectl -n "${namespace}" exec -c ingest $(kubectl get pods -n "${namespace}" -l "app=eric-data-search-engine,role in (ingest-tls,ingest)" -o jsonpath="{.items[0].metadata.name}") -- /bin/esRest"
   $esRest GET /_cat/nodes?v>"${log_base_path}"/logs/SE/nodes.txt
   $esRest GET /_cat/indices?v>"${log_base_path}"/logs/SE/indices.txt
   $esRest GET /_cluster/health?pretty > "${log_base_path}"/logs/SE/health.txt
   $esRest GET /_cluster/allocation/explain?pretty > "${log_base_path}"/logs/SE/allocation.txt
    fi
   mkdir "${log_base_path}"/logs/sip_kms_dced/DCED
   for i in `kubectl --namespace "${namespace}" get pod |grep data-distributed-coordinator-ed|grep -v agent|awk '{print $1}'`
   do
           echo $i
           kubectl --namespace "${namespace}" exec $i -c dced -- etcdctl member list -w fields >  "${log_base_path}"/logs/sip_kms_dced/DCED/memberlist_$i.txt
           kubectl --namespace "${namespace}" exec $i  -c dced -- bash  -c 'ls /data/member/snap -lh' >  "${log_base_path}"/logs/sip_kms_dced/DCED/sizedb_$i.txt
           kubectl --namespace "${namespace}" exec $i  -c dced -- bash  -c 'du -sh data/*;du -sh data/member/*;du -sh data/member/snap/db' >>  "${log_base_path}"/logs/sip_kms_dced/DCED/sizedb_$i.txt
#           kubectl --namespace "${namespace}" exec $i -- etcdctl  endpoint status --endpoints=:2379 --insecure-skip-tls-verify=true -w fields>  "${log_base_path}"/logs/sip_kms_dced/DCED/endpoints_$i.txt
           kubectl --namespace "${namespace}" exec $i  -c dced -- bash -c 'unset ETCDCTL_ENDPOINTS; etcdctl endpoint status --endpoints=:2379 --insecure-skip-tls-verify=true -w fields'> "${log_base_path}"/logs/sip_kms_dced/DCED/endpoints_$i.txt
           kubectl --namespace "${namespace}" exec $i  -c dced -- etcdctl user list >  "${log_base_path}"/logs/sip_kms_dced/DCED/user_list$i.txt
   done
   if (kubectl --namespace="${namespace}" get pods | grep -i kvdb-ag)
      then
      mkdir "${log_base_path}"/logs/KVDBAG


#   for i in `kubectl --namespace "${namespace}" get pods|grep -i kvdb-ag|awk '{print $1}'`
   for i in `cd  "${log_base_path}"/describe/PODS/; grep eric-data-kvdb-ag *| grep Image:|awk -F\: '{print $1}' |sort -u| awk -F\. '{print $1}'`
   do
           mkdir  "${log_base_path}"/logs/KVDBAG/$i
           mkdir  "${log_base_path}"/logs/KVDBAG/$i/logs
           mkdir  "${log_base_path}"/logs/KVDBAG/$i/stats
        for j in `kubectl --namespace "${namespace}" exec $i -- ls /opt/dbservice/data/logs/ 2>/dev/null`
                do 
        kubectl --namespace "${namespace}" cp $i:/opt/dbservice/data/logs/$j "${log_base_path}"/logs/KVDBAG/$i/logs/$j 2>/dev/null
                done
        for j in `kubectl  --namespace "${namespace}" exec $i -- ls -ltr /opt/dbservice/data/stats/|tail -3|grep  -vi marker| awk '{print $9}' 2>/dev/null`
        do
  kubectl --namespace "${namespace}" cp $i:/opt/dbservice/data/stats/$j "${log_base_path}"/logs/KVDBAG/$i/stats/$j 2>/dev/null&
        done
   done
  fi
  }
  get_ss7_cnf() {

  if (kubectl --namespace="${namespace}" get pods | grep -i ss7)
      then

  for i in `kubectl --namespace "${namespace}" get pod -o json | jq -r '.items[] | select(.spec.containers[].name=="ss7") | .metadata.name'`
    do
      cnfpath="${log_base_path}"/ss7_cnf_$i
      mkdir $cnfpath
      kubectl --namespace "$namespace" cp $i:/opt/cnf-dir/ -c ss7 ${cnfpath}
    done
  fi
}
sm_log() {

    #echo "-----------------------------------------"
    echo "-Verifying for SM logs -"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"
  
    sm_log_dir=${log_base_path}/logs/sm_log
    serviceMeshCustomResources=("adapters.config" "attributemanifests.config" "authorizationpolicies.security" "destinationrules.networking" "envoyfilters.networking" "gateways.networking" "handlers.config" "httpapispecbindings.config" "httpapispecs.config" "instances.config" "peerauthentications.security" "proxyconfigs.networking" "quotaspecbindings.config" "quotaspecs.config" "rbacconfigs.rbac" "requestauthentications.security" "rules.config" "serviceentries.networking" "servicerolebindings.rbac" "serviceroles.rbac" "sidecars.networking" "telemetries.telemetry" "templates.config" "virtualservices.networking" "wasmplugins.extensions" "workloadentries.networking" "workloadgroups.networking")
    istioDebugURL=("adsz" "syncz" "registryz" "endpointz" "instancesz" "endpointShardz" "configz" "cachez" "resourcesz" "authorizationz" "push_status" "inject" "mesh" "networkz")
    proxyDebugURL=("certs" "clusters" "config_dump?include_eds" "listeners" "memory" "server_info" "stats/prometheus" "runtime")
    if (kubectl --namespace=${namespace} get pods --selector app=istiod | grep eric-mesh-controller | grep Running)
    then
      mkdir -p ${sm_log_dir}/istio
      echo "SM Controller pods found running, gathering sm_log for controller pods..."
      for pod_name in `kubectl --namespace=${namespace} get pods --selector app=istiod --no-headers | awk -F " " '{print $1}'`
        do
          mkdir -p ${sm_log_dir}/istio/$pod_name/debug
          for debug_path in ${istioDebugURL[@]}
            do
              kubectl --namespace ${namespace} exec ${pod_name} -c discovery -- curl --silent http://localhost:15014/debug/${debug_path} > ${sm_log_dir}/istio/${pod_name}/debug/${debug_path}
            done
        done
      if (kubectl --namespace=${namespace} get crd | grep istio.io >/dev/null)
      then
        echo "SM Controller CRDs have been found, looking for applied CRs..."
        for sm_crs in ${serviceMeshCustomResources[@]}
          do
            if [[ $(kubectl --namespace ${namespace} get ${sm_crs}.istio.io --ignore-not-found) ]]
            then
              sm_cr=$(echo ${sm_crs} | awk -F "." '{print $1}')
              mkdir -p ${sm_log_dir}/ServiceMeshCRs/${sm_cr}
              echo "Applied ${sm_cr} CR has been found, gathering sm_log for it..."
              for resource in `kubectl --namespace ${namespace} get ${sm_crs}.istio.io --no-headers | awk -F " " '{print $1}'`
                do 
                  kubectl --namespace ${namespace} get ${sm_crs}.istio.io ${resource} -o yaml > ${sm_log_dir}/ServiceMeshCRs/${sm_cr}/${resource}.yaml
                done
            fi
          done
      else
        echo "No SM Controller CRD has been found!"
      fi
      if (kubectl --namespace=${namespace} get pods -o jsonpath='{.items[*].spec.containers[*].name}' | grep istio-proxy)
      then
        mkdir -p ${sm_log_dir}/proxies
        echo "Pods with istio-proxy container are found, gathering sm_log for pods with istio-proxy..."
        for pod_name in `kubectl --namespace=${namespace} get pods -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{": "}{range .spec.containers[*]}{.name}{" "}{end}{end}' | grep istio-proxy | awk -F ":" '{print $1}'`
          do  
            mkdir ${sm_log_dir}/proxies/${pod_name}
            for debug_path in ${proxyDebugURL[@]}
              do
                if [[ ${debug_path} == "stats/prometheus" ]]; then
                  mkdir ${sm_log_dir}/proxies/${pod_name}/stats
                fi
                kubectl --namespace ${namespace} exec ${pod_name} -c istio-proxy -- curl --silent http://localhost:15000/${debug_path} > ${sm_log_dir}/proxies/${pod_name}/${debug_path}
              done
          done
      else
        echo "Pods with istio-proxy containers are not found or not running, doing nothing"
      fi
    else
       echo "ServiceMesh Controller pods are not found or not running, doing nothing"
    fi
}


compress_files() {
    echo "Generating tar file and removing logs directory..."
    tar cfz $PWD/${log_base_dir}.tgz ${log_base_dir}
    echo  -e "\e[1m\e[31mGenerated file $PWD/${log_base_dir}.tgz, Please collect and send to ADP Support!\e[0m"
    rm -r $PWD/${log_base_dir}
}

get_describe_info
get_events
get_pods_logs
get_helm_info
cmm_log
siptls_logs
cmy_log
diameter_log
basic_checks
get_ss7_cnf
sm_log
compress_files

