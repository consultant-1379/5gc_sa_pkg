#!/bin/bash
############################################################################
# Used version of collect_ADP_logs : 18 May 2022
# https://eteamspace.internal.ericsson.com/x/7FihQw
#
# To use, execute collect_UDR_metrics.sh <namespace>
#
# collect_UDR_info.sh confluence: https://eteamspace.internal.ericsson.com/x/lGqRO
#
############################################################################
VERSION="0.8"
printUsage() {
  echo "Usage: $0 [OPTIONS] <k8s_namespace>"
  echo
  echo "OPTIONS:"
  echo "  -h           --help             Show this information"
  echo "  -v           --version          Displays collect_UDR_metrics version"
  echo "  -t           --status           Get status from k8s_namespace"
  echo "  -i           --info             Get information from k8s_namespace"
  echo "  -c           --counters         Get counters from k8s_namespace, affected by -s and -e"
  echo "  -m           --monitoring       Get counters from monitoring k8s_namespace, affected by -s and -e"
  echo "    -f=\"regex\" --filterCounters   Filter to retrieve only the counters that match the regex"
  echo "                                    (affects -c and -m)"
  echo "  -l           --logs             Get logs from kubectl logs"
  echo "               --elastic          Modify --logs, obtaining them from ElasticSearch"
  echo "    -b=\"regex\" --filterContainers Filter to retrieve logs from containers matching the regex"
  echo "    -p=\"regex\" --filterPods       Filter to retrieve logs from pods matching the regex"
  echo "  -s=date      --start=date       Initial time of the recovered data"
  echo "  -e=date      --end=date         Final time of the recovered data"
  echo "date format: yyyymmdd_HHMMSS"
  echo
  echo "EXCLUSIVE OPTIONS:"
  echo "  KVDB"
  echo "  -k           --kvdb             Get logs/counters from kvdb-ag-server "
  echo "    AVAILABLE FLAGS:"
  echo "    -l           --logs             Obtain files from logs folder inside pod"
  echo "    -t           --status           Obtain files from stats folder inside pod"
  echo "    -p=\"replica_id_1|replica_id_n\" --filterPods       List of server \"pods ids\" or \"all\" from where to take the specified files"
  echo "    -n=\"n_recent_files\"            --nfiles           Filter to obtain last n_recent_files from pod"
  echo "  EsRest"
  echo "  -r           --esrest           Get logs from ElasticSearch, affected by -s and -e"
  echo "    AVAILABLE FLAGS:"
  echo "    -p=\"regex\" --filterPods       Filter logs applying the regex to pods names"
  echo
  echo "DEFAULT VALUES:"
  echo " GLOBAL:"
  echo "  -s     --start         =  Actual time - 1 hour"   
  echo "  -e     --end           =  Actual time"
  echo "            IMPORTANT:      Actual Time is the time in the host were the command is executed"
  echo "  kubernetes_namespace   =  current context namespace or detected via Helm if absent"
  echo "  by default it gets info, status, counters and logs with adp extra logs and checks"
  echo "     equivalent to -c -t -i -l --adp"
  echo " KVDB"
  echo "  replica_set_id default value: all"
  echo "  n_recent_files default value: all"
  echo
  echo "EXAMPLES:"
  echo "   $0 -s 20220605_103020 -e 20220605_104030                              Collect data between two dates (end only applied to counters)"
  echo "   $0 --start 20220605_103020 --end 20220605_104030 \"k8s_namespace\""   
  echo "   $0 -c -s 20220605_103020 -e 20220605_104030"                          Collect only counters data between specified dates
  echo "   $0 -m -f \"^counters|kvdb|udr\" \"k8s_namespace\""
  echo "   $0 --counters --filterCounters \"^counters|kvdb|udr|envoy\" -s 20220620_103020 -e 20220620_104030"
  echo "   $0 -l -p \"security|app\" \"k8s_namespace\""
  echo "   $0 --logs --filterPods \"security|app\""
  echo "   $0 -l --elastic"
  echo "   $0 --info --status \"k8s_namespace\""
  echo "   $0 -i -t \"k8s_namespace\""
  echo
  echo "   $0 --kvdb [-l|-t] -p \"replica_set_id[|replica_set_id2]|all\" -n \"n_recent_files|all\""
  echo "   $0 -k                           Gets logs and stats from kvdb all pods"
  echo "   $0 -k -l -p \"0|1\" -n \"3\"    Gets last 3 log files from kvdb pod kvdb-ag-0 kvdb-ag-1"
  echo "   $0 -k -t -p \"all\" -n \"10\"   Gets last status file from all pods"
  echo 
  echo "   $0 --esrest --filterPods \"pod_name\" -s \"since_timestamp\" -e \"end_timestamp\""
  echo "   $0 -r --start 20220524_090500 --end 20220524_091000  Collects logs from all pods from ELastic search in the specified time range"
}
printWarning() {
  echo -e "\e[1;33mWarning:\e[0m $1"
}
compress_files() {
  echo "Generating tar file and removing logs directory..."
  tar cfz $PWD/${base_dir}.tgz --remove-files ${base_dir}
  echo -e "\e[1m\e[31mGenerated file $PWD/${base_dir}.tgz Please collect and send to UDR Support!\e[0m"
}
############### INFO FUNCTIONS ##############################################
get_cluster_inventory() {
  echo "-Getting software inventory info by POD"
  kubectl -n "${namespace}" get pods -o jsonpath='{range .items[?(@.metadata.namespace == '\"$namespace\"')]}{.metadata.name}{"\n\tName: "}{.metadata.labels.app}{"\n\tLabels: "}{.metadata.labels}{"\n\tContainers image inventory:\n\t\tname\timage\n"}{range .spec.containers[*]}{"\t\t"}{.name}{"\t"}{.image}{"\n"}{end}' >$info_dir/inventory.log
}
get_cluster_resources() {
  echo "-Getting cluster resources info"
  local rs_log_dir=$info_dir/cluster_resources
  mkdir ${rs_log_dir}
  kubectl -n "${namespace}" top node > ${rs_log_dir}/top_node_output.txt
  kubectl -n "${namespace}" top pods > ${rs_log_dir}/top_pods_output.txt
  command -v jq >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    local RESOURCE_CONSUMED_LOG_FILE=${rs_log_dir}/pods-resources-consumed.txt
    echo "#PODs resources consumed in the cluster" >$RESOURCE_CONSUMED_LOG_FILE
    echo "#namespace,POD name" >>$RESOURCE_CONSUMED_LOG_FILE
    echo "#  container name,cpu consumed,memory consumed" >>$RESOURCE_CONSUMED_LOG_FILE
    kubectl -n "${namespace}" get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq -jr '.items[] | select (.metadata.namespace == '\"$namespace\"') | .metadata.namespace, ",", .metadata.name,  (.containers[] | "\n\t", .name, ",", .usage.cpu, ",", .usage.memory), "\n"' >>$RESOURCE_CONSUMED_LOG_FILE
  fi
  local RESOURCE_SCHEDULED_LOG_FILE=${rs_log_dir}/pods-resources-scheduled.log
  echo "#PODs resources scheduled in the cluster" >$RESOURCE_SCHEDULED_LOG_FILE
  echo "#namespace,POD name" >>$RESOURCE_SCHEDULED_LOG_FILE
  echo "#  container name,cpu request,memory request,cpu limit, memory limit" >>$RESOURCE_SCHEDULED_LOG_FILE
  kubectl -n "${namespace}" get pods -o jsonpath='{range .items[?(@.metadata.namespace == '\"$namespace\"')]}{.metadata.namespace}{","}{.metadata.name}{"\n"}{range .spec.containers[*]}{"\t"}{.name}{","}{.resources.requests.cpu}{","}{.resources.requests.memory}{","}{.resources.limits.cpu}{","}{.resources.limits.memory}{"\n"}{end}' >>$RESOURCE_SCHEDULED_LOG_FILE
}
get_describe_info() {
  echo "-Getting describe_info"
  local output=""
  local des_dir=$info_dir/describe
  mkdir ${des_dir}
  for attr in statefulsets deployments services replicasets endpoints daemonsets persistentvolume persistentvolumeclaims configmap pods nodes jobs persistentvolumes rolebindings roles secrets serviceaccounts storageclasses ingresses gateways virtualservices destinationrules serviceentries; do
    local dir=$(echo $attr | tr '[:lower:]' '[:upper:]')
    [ -d ${des_dir}/${dir} ] || mkdir ${des_dir}/${dir}
    kubectl --namespace ${namespace} get $attr -o wide >${des_dir}/$dir/$attr.txt
    echo "Getting describe information on $dir..."
    for i in $(kubectl --namespace ${namespace} get $attr | grep -v NAME | awk '{print $1}'); do
      kubectl --namespace ${namespace} get $attr $i -o yaml > ${des_dir}/$dir/$i.yaml &
      while [ $(jobs | wc -l) -gt 10 ]; do
        sleep 2 
      done
    done
  done
  
  for attr in $( kubectl api-resources --verbs=list --namespaced --no-headers |egrep -vi "events|statefulsets|internalCertificates|crd|deployments|services|replicasets|endpoints|daemonsets|persistentvolumeclaims|configmap|pod|nodes|jobs|persistentvolumes|rolebindings|roles|secrets|serviceaccounts|storageclasses|ingresses|httpproxy"| sed 's/true/;/g'| awk -F\; '{print $2}')  
  do
    dir=`echo $attr | tr '[:lower:]' '[:upper:]'`
    mkdir -p ${des_dir}/OTHER/$dir
    kubectl --namespace ${namespace} get $attr  -o wide > ${des_dir}/OTHER/$dir/$attr.txt
    echo "Getting describe information on $dir.."
    for i in `kubectl --namespace ${namespace} get $attr | grep -v NAME | awk '{print $1}'`
    do
      kubectl --namespace ${namespace}  get  $attr  $i -o yaml > ${des_dir}/OTHER/$dir/$i.yaml &
      while [ $(jobs | wc -l) -gt 10 ]; do
        sleep 2 
      done
    done
  done
  wait
  echo -e "--- Describe_info: finished. All steps executed \n${output}"
}
get_envoy_config() {
  #To avoid perl error while executing from the director
  # Apart from this this function has to be executed NOT in background
  export LC_CTYPE=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  local httpproxy_log_dir=$info_dir/udr_http_proxy
  mkdir -p $httpproxy_log_dir
#  echo "---getting envoy config for POD $1 "
  for i in $(kubectl get pods -n "${namespace}" -l app=$1 -o jsonpath='{.items..metadata.name}'); do
    kubectl exec -n "${namespace}" -i $i -c $1 -- curl -s http://localhost:9901/config_dump >${httpproxy_log_dir}/http-proxy-$i.log
  done
}
get_helm_info() {
  echo "-Getting Helm Charts for the deployments-"
  local helm_dir=$info_dir/helm
  mkdir ${helm_dir}
  # Check helm version
  helm version | head -1 >$helm_dir/helm_version.txt
  if [ -n "$(grep v3 $helm_dir/helm_version.txt)" ]; then
    #echo "HELM 3 identified"
    local HELM='helm get all --namespace='${namespace}
  else
    local HELM='helm get --namespace='${namespace}
    #echo "$HELM"
  fi
  # Get helm charts
  helm --namespace "${namespace}" list >${helm_dir}/helm_deployments.txt
  for i in $(helm --namespace "${namespace}" list | grep -v NAME | awk '{print $1}'); do
    #echo "---getting Helm chart for $i "
    $HELM $i >${helm_dir}/$i.txt
  done
}
get_http_proxy_config() {
  echo "-Getting HTTP Proxy config"
  get_envoy_config "eric-udr-provisioningfe"
  get_envoy_config "eric-udr-notificationsubscription"
  get_envoy_config "eric-udr-nudrfe"
}
get_istio_config() {
  echo "-Getting istio config from ingress gws"
  local istio_log_dir=$info_dir/udr_istio
  mkdir ${istio_log_dir}
  for i in $(kubectl get pods -n "${namespace}" -l app=ingressgateway -o jsonpath='{.items..metadata.name}'); do
    kubectl exec -n "${namespace}" -i $i -c istio-proxy -- curl -s http://localhost:15000/config_dump >${istio_log_dir}/istio-config-$i.log
  done
}
get_kafka_info() {
  echo "-Getting Kafka info"
  local kafka_log_dir=${info_dir}/kafka_info
  mkdir ${kafka_log_dir}
  local NAME="eric-udr-message-bus-kf"
  kubectl exec -n "${namespace}" -i ${NAME}-0 -c messagebuskf -- cat /etc/kafka/kafka.properties >${kafka_log_dir}/kafka_configuration.txt
  kubectl exec -n "${namespace}" -i ${NAME}-0 -c messagebuskf -- kafka-topics --describe --bootstrap-server ${NAME}:9092 >${kafka_log_dir}/kafka_topics.txt
  kubectl exec -n "${namespace}" -i ${NAME}-0 -c messagebuskf -- kafka-consumer-groups --list --bootstrap-server ${NAME}:9092 >${kafka_log_dir}/kafka_consumer_groups.txt
  kubectl exec -n "${namespace}" -i ${NAME}-0 -c messagebuskf -- kafka-consumer-groups --describe --group rest-notifsenders --bootstrap-server ${NAME}:9092 >${kafka_log_dir}/kafka_consumers_rest-notifsenders.txt
  kubectl exec -n "${namespace}" -i ${NAME}-0 -c messagebuskf -- kafka-consumer-groups --describe --group soap-notifsenders --bootstrap-server ${NAME}:9092 >${kafka_log_dir}/kafka_consumers_soap-notifsenders.txt
  kubectl exec -n "${namespace}" -i ${NAME}-0 -c messagebuskf -- kafka-consumer-groups --describe --group rest-notifcheckers --bootstrap-server ${NAME}:9092 >${kafka_log_dir}/kafka_consumers_rest-notifsenders.txt
  kubectl exec -n "${namespace}" -i ${NAME}-0 -c messagebuskf -- kafka-consumer-groups --describe --group soap-notifcheckers --bootstrap-server ${NAME}:9092 >${kafka_log_dir}/kafka_consumers_soap-notifsenders.txt
}
get_prom_info() {
  echo "-Getting Prometheus information"
  local out="${info_dir}/prometheus_info.txt"
  local QUERY="sort (count ({__name__=~\".+\"}) )"
  local nSeries=$(kubectl exec -n "${namespace}" eric-pm-server-0 -c eric-pm-server -- promtool query instant http://localhost:9090 "${QUERY}" | awk '{print $3}')
  #Check the counters that are now in pm-server and send it to a list to check:
  local nCounters=$(kubectl exec -n "${namespace}" deploy/eric-udr-system-status-provider -c eric-udr-system-status-provider -- curl -s http://eric-pm-server:9090/api/v1/label/__name__/values | sed s/\",\"/"\n"/g | wc -l)
  #Check the 50 counters with more series on each environments:
  local QUERY="sort (count by (__name__)({__name__=~\".+\"}) )"
  local table="$(kubectl exec -n "${namespace}" eric-pm-server-0 -c eric-pm-server -- promtool query instant http://localhost:9090 "${QUERY}" | awk '{print $1 " " $3}' | column -t)"
  echo -e "Num Counters: $nCounters\nNum Series: $nSeries\n" >$out
  echo -e "Top 20 counters:\n$table" >>$out
}
get_udr_config() {
  echo "-Getting UDR configuration"
  local udr_cm_log_dir=${info_dir}/udr_cm_config
  mkdir ${udr_cm_log_dir}
  command -v jq >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    kubectl exec -n "${namespace}" deploy/eric-cm-mediator -c eric-cm-mediator -- curl -s http://localhost:5003/cm/api/v1/configurations/ericsson-udr | jq . >${udr_cm_log_dir}/udr_cm_config.txt
  else
    kubectl exec -n "${namespace}" deploy/eric-cm-mediator -c eric-cm-mediator -- curl -s http://localhost:5003/cm/api/v1/configurations/ericsson-udr >${udr_cm_log_dir}/udr_cm_config.txt
  fi
}
cmy_log() {
  echo "-Verifying for CM Yang logs and schemas -"
  local cmy_log_dir=${info_dir}/cmy_log
  local yangPods=$(kubectl -n "${namespace}" get pods | grep -i yang | grep Running | awk '{print $1}')
  if [ -n "$yangPods" ]; then
    #echo "CM Yang Pods found running, gathering cmyang_logs.."
    for i in "$yangPods"; do
      mkdir -p ${cmy_log_dir}/sssd_$i/
      kubectl -n "${namespace}" cp $i:/var/log/sssd ${cmy_log_dir}/sssd_$i/ -c sshd > /dev/null
    done
  else
    echo "CM Yang Containers not found or not running, skipping..."
  fi
  cmyp_yang_schemas ${cmy_log_dir}
  cmyp_json_schemas ${cmy_log_dir}
}
cmyp_json_schemas() {
  echo "-Collect JSON schemas-"
  local cmy_log_dir=$1
  if [ "$(kubectl get pod -n "${namespace}" | grep -i document-database-pg-cm)" ]
  then
    local ddb=`kubectl get pod -n "${namespace}" | grep -i 'document-database-pg-cm'  | grep Running | head -n 1 | awk '{print $1}'`
  else
    local ddb=`kubectl get pod -n "${namespace}" | grep -i 'document-database-pg'  | grep Running | head -n 1 | awk '{print $1}'`
  fi
  local DDB_CMD="kubectl exec ${ddb} -n ${namespace} -c eric-data-document-database-pg -- /usr/bin/bash -c"
  local JSON_PATH=$(mktemp -d -u "/tmp/jsonSchemas.XXXXXX")
  local LOCAL_PATH=${cmy_log_dir}/schemas_${ddb}/
  mkdir -p ${LOCAL_PATH}
  ${DDB_CMD} "if [ -d ${JSON_PATH} ]; then rm -rf ${JSON_PATH}; fi; mkdir ${JSON_PATH}"
  local jsonNames=$(${DDB_CMD} "echo \"SELECT name FROM schemas\" | /usr/bin/psql --quiet --tuples-only -d adp_gs_cm -U postgres")
  for n in ${jsonNames}; do
    #echo fetch ${n}
    local fetch="echo \"SELECT data->'schema' FROM schemas WHERE name='${n}'\" | /usr/bin/psql --quiet --tuples-only -d adp_gs_cm -U postgres > ${JSON_PATH}/${n}.json"
    ${DDB_CMD} "${fetch}"
    #echo fetch ${n} done
  done
  ${DDB_CMD} "cd ${JSON_PATH} && tar -czf jsonSchemas.tar.gz *"
  kubectl cp ${ddb}:${JSON_PATH}/jsonSchemas.tar.gz ${LOCAL_PATH}/jsonSchemas.tar.gz -n ${namespace} -c eric-data-document-database-pg > /dev/null 
  tar xzvf ${LOCAL_PATH}/jsonSchemas.tar.gz -C ${LOCAL_PATH}/ 1> /dev/null
  rm -f ${LOCAL_PATH}/jsonSchemas.tar.gz
  ${DDB_CMD} "rm -rf ${JSON_PATH}"
}
cmyp_yang_schemas() {
  #echo "-----------------------------------------"
  echo "-Collect YANG schemas-"
  #echo "-----------------------------------------"
  local cmy_log_dir=$1
  YANG_POD=$(kubectl get pods | grep yang | awk '{print $1}')
  DBNAME=$(kubectl describe pod ${YANG_POD} | grep POSTGRES_DBNAME | head -1 | awk '{print $2}')
  if [ "$(kubectl get pod -n "${namespace}" | grep -i document-database-pg-cm)" ]
  then
    local ddb=`kubectl get pod -n "${namespace}" | grep -i 'document-database-pg-cm'  | grep Running | head -n 1 | awk '{print $1}'`
  else
    local ddb=`kubectl get pod -n "${namespace}" | grep -i 'document-database-pg'  | grep Running | head -n 1 | awk '{print $1}'`
  fi
  local DDB_CMD="kubectl exec ${ddb} -n ${namespace} -c eric-data-document-database-pg -- /usr/bin/bash -c"
  local YANG_PATH=$(mktemp -d -u "/tmp/yangSchemas.XXXXXX")
  local LOCAL_PATH=${cmy_log_dir}/schemas_${ddb}/
  mkdir -p ${LOCAL_PATH}
  local yangNames=$(${DDB_CMD} "echo \"SELECT name FROM yangschemas\" | /usr/bin/psql --quiet --tuples-only -d adp_gs_cm -U postgres")
  ${DDB_CMD} "if [ -d ${YANG_PATH} ]; then rm -rf ${YANG_PATH}; fi; mkdir ${YANG_PATH}"
  for n in ${yangNames}; do
    #echo fetch ${n}
    local fetch="echo \"SELECT data FROM yangschemas WHERE name='${n}'\" | /usr/bin/psql --quiet --tuples-only -d \"${DBNAME}\" -U postgres > ${YANG_PATH}/${n}"
    ${DDB_CMD} "${fetch}"
    #echo fetch ${n} done
  done
  ${DDB_CMD} "cd ${YANG_PATH} && tar -czf yangSchemas.tar.gz *"
  kubectl cp ${ddb}:${YANG_PATH}/yangSchemas.tar.gz ${LOCAL_PATH}/yangSchemas.tar.gz -n ${namespace} -c eric-data-document-database-pg > /dev/null
  tar xzvf ${LOCAL_PATH}/yangSchemas.tar.gz -C ${LOCAL_PATH}/  1> /dev/null
  rm -f ${LOCAL_PATH}/yangSchemas.tar.gz
  for f in ${LOCAL_PATH}/*; do
    cat ${f} | $(which xxd) -r -p >${f}.tar.gz
    rm -f ${f}
  done
  ${DDB_CMD} "rm -rf ${YANG_PATH}"
}
cmm_collect_logs() {
  echo "-Verifying for CM logs -"
  local cmm_log_dir=${info_dir}/cmm_log
  local cmPods="$(kubectl -n "${namespace}" get pods | grep cm-mediator | grep Running | awk '{print $1}')"
  if [ -n "$cmPods" ]; then
    mkdir ${cmm_log_dir}
    #echo "CM Pods found running, gathering cmm_logs.."
    for i in $cmPods; do
      kubectl exec -n "${namespace}" $i -c eric-cm-mediator -- collect_logs >${cmm_log_dir}/cmmlog_$i.tgz
    done
    #echo "---Gathering cmm schemas & configuration"
    #Checking for schemas and configurations
    local POD_NAME=$(echo "$cmPods" | grep -vi notifier | head -1)
    kubectl --namespace "${namespace}" exec "${POD_NAME}" -c eric-cm-mediator -- curl -sX GET http://localhost:5003/cm/api/v1/schemas | json_pp >${cmm_log_dir}/schemas.json 2>/dev/null
    kubectl --namespace "${namespace}" exec "${POD_NAME}" -c eric-cm-mediator -- curl -sX GET http://localhost:5003/cm/api/v1/configurations | json_pp >${cmm_log_dir}/configurations.json 2>/dev/null
    local configurations_list=$(cat ${cmm_log_dir}/configurations.json | grep \"name\" | cut -d : -f 2 | tr -d \",)
    for i in $configurations_list; do
      kubectl --namespace ${namespace} exec $POD_NAME -c eric-cm-mediator -- curl -sX GET http://localhost:5003/cm/api/v1/configurations/$i | json_pp >${cmm_log_dir}/config_$i.json
    done
  else
    echo "CM Containers not found or not running, skipping..."
  fi
}
############### STATUS FUNCTIONS ##############################################
get_events() {
  echo "-Getting list of events-"
  des_dir=$status_dir/describe/EVENTS
  mkdir -p ${des_dir}
  kubectl -n "${namespace}" get events >${des_dir}/events.txt
}
get_geode_info() {
  echo "-Getting Geode status"
  local geode_log_dir=$status_dir/geode_info
  mkdir ${geode_log_dir}
  kubectl exec -n "${namespace}" -i eric-udr-kvdb-ag-locator-0 -c eric-udr-kvdb-ag-locator -- gfsh -e "connect --locator=localhost[10334]" -e "list members" -e "describe config --member eric-udr-kvdb-ag-server-0" -e "list clients" -e "list deployed" -e "list regions" -e "list indexes --with-stats" -e "query --query='SELECT * from /NotifSubscriptions limit 3'" -e "query --query='SELECT count(*) from /NotifSubscriptions'" -e "list gateways" -e "show missing-disk-stores" >${geode_log_dir}/geode_info.txt
}
get_netstat() {
  #To avoid perl error while executing from the director
  export LC_CTYPE=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  #echo "---getting connection info for PODs with app=$1, container=$2"
  if [ "$1" == "eric-udr-kvdb-ag-server" ]; then
    local podlist=$(kubectl -n "${namespace}" get pods | grep eric-udr-kvdb-ag-server | awk '{print $1}')
  elif [ "$1" == "eric-udr-kvdb-ag-locator" ]; then
    local podlist=$(kubectl -n "${namespace}" get pods | grep eric-udr-kvdb-ag-locator | awk '{print $1}')
  else
    local podlist=$(kubectl get pods -n "${namespace}" -l app=$1 -o jsonpath='{.items..metadata.name}')
  fi
  for pod in ${podlist}; do
    kubectl exec -n "${namespace}" -i ${pod} -c $2 -- awk '
function hextodec(str,ret,n,i,k,c){
    ret = 0
    n = length(str)
    for (i = 1; i <= n; i++) {
        c = tolower(substr(str, i, 1))
        k = index("123456789abcdef", c)
        ret = ret * 16 + k
    }
    return ret
}
function getIP(str,ret){
    ret=hextodec(substr(str,index(str,":")-2,2)); 
    for (i=5; i>0; i-=2) {
        ret = ret"."hextodec(substr(str,i,2))
    }
    ret = ret":"hextodec(substr(str,index(str,":")+1,4))
    return ret
}
NR > 1 {{if(NR==2)print "Local - Remote";local=getIP($2);remote=getIP($3)}{print local" - "remote}}' /proc/net/tcp >${conn_log_dir}/netstat_${pod}_$2.log
    kubectl exec -n "${namespace}" -i ${pod} -c $2 -- ss 2>/dev/null >${conn_log_dir}/ss_${pod}_$2.log
  done
}
get_pods_ips_status() {
  echo "-Getting Pods IPs"
  local cluster_pods_ips_status_log_txt=$status_dir/cluster_pods_ips_status.txt
  kubectl -n "${namespace}" get pods -o wide --all-namespaces >${cluster_pods_ips_status_log_txt}
}
# ALARMS
get_udr_alarms() {
  echo "-Getting alarms: summary, list and history"
  #echo "--Alarms summary"
  kubectl -n "${namespace}" exec deploy/eric-fh-alarm-handler -c eric-fh-alarm-handler -- curl -s http://localhost:5005/ah/api/v0/alarms?outputFormat=SeveritySummary >${status_dir}/alarms.log
  #echo "--List of alarms"
  echo "" >>${status_dir}/alarms.log
  kubectl -n "${namespace}" exec deploy/eric-fh-alarm-handler -c eric-fh-alarm-handler  -- curl -s http://localhost:5005/ah/api/v0/alarms >>${status_dir}/alarms.log
  #echo "--Alarms history"
  echo "" >>${status_dir}/alarms.log
  alarms_history_file=${status_dir}/alarms-history.log
  echo "#################################### Alarms indexes in datasearch engine ####################################" > ${alarms_history_file}
  kubectl -n "${namespace}" exec deploy/eric-fh-alarm-handler -c eric-fh-alarm-handler -- curl -s http://eric-data-search-engine:9200/_cat/indices?v | grep asi | sort >> ${alarms_history_file}
  local searchEngine="eric-data-search-engine-data-0"
  echo -e "\n#################################### Alarms in last two days ####################################" >> ${alarms_history_file}
  echo "timestamp | severity | message | update number | name |description " | column -t >> ${alarms_history_file}
  #The expresion %3Cadp-app-asi-logs-%7Bnow%2Fd%7D%3E%3Cadp-app-asi-logs-%7Bnow%2Fd%7D%3E is standard in elastic to get the data from the last two days of logs
  kubectl exec -n "${namespace}" -i ${searchEngine} -c data -- esRest GET '/%3Cadp-app-asi-logs-%7Bnow%2Fd%7D%3E%3Cadp-app-asi-logs-%7Bnow%2Fd%7D%3E/_search?size=10000&pretty' --data "{\"sort\": [{\"timestamp\": {\"order\": \"asc\"}}]}" | jq 'select (.hits.hits != null) | .hits.hits[]._source | .timestamp as $time | .severity as $severity | .message as $message | .extra_data.asi | .alarmUpdate as $alarmUpdate | .alarmName as $name | .description as $desc | {time: $time, severity: $severity, message: $message, a: $alarmUpdate|tostring, name: $name,  desc: $desc} | join("@") '| sed s/\"//g | column -s "@" -t >> ${alarms_history_file}
}
get_udr_connections() {
  echo "-Getting connections info"
  local conn_log_dir=$status_dir/udr_net
  mkdir ${conn_log_dir}
  get_netstat "eric-udr-kvdb-ag-server" "eric-udr-kvdb-ag-server"
  get_netstat "eric-udr-kvdb-ag-locator" "eric-udr-kvdb-ag-locator"
  get_netstat "eric-udr-ldap-balancer" "eric-udr-ldap-balancer"
  get_netstat "eric-udr-ldapfe" "eric-udr-ldapfe"
  get_netstat "eric-udr-ldapfe" "eric-udr-query-router" #ss not available yet in qr
  get_netstat "eric-udr-nudrfe" "eric-udr-nudrfe"
  get_netstat "eric-udr-nudrfe" "eric-udr-query-router" #ss not available yet in qr
  get_netstat "eric-udr-provisioningfe" "eric-udr-provisioningfe"
  get_netstat "eric-udr-provisioningfe" "eric-udr-query-router" #ss not available yet in qr
  get_netstat "eric-udr-notificationsubscription" "eric-udr-notificationsubscription"
  get_netstat "eric-udr-notificationsubscription" "eric-udr-query-router" #ss not available yet in qr
  get_netstat "eric-udr-rest-notifsender" "eric-udr-rest-notifsender"
  get_netstat "eric-udr-rest-notifchecker" "eric-udr-rest-notifchecker"
  get_netstat "ingressgateway" "istio-proxy"
}
get_udr_system_status() {
  echo "-Getting UDR System Status"
  local udr_status_log_dir=$status_dir/udr_status
  mkdir ${udr_status_log_dir}
  command -v jq >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    kubectl exec -n "${namespace}" deploy/eric-udr-system-status-provider -c eric-udr-system-status-provider -- curl -s http://localhost:8080/udr-status/v1/status | jq . >${udr_status_log_dir}/udr_system_status.json
  else
    kubectl exec -n "${namespace}" deploy/eric-udr-system-status-provider -c eric-udr-system-status-provider -- curl -s http://localhost:8080/udr-status/v1/status >${udr_status_log_dir}/udr_system_status.json
  fi
}
# UDR Topology
get_udr_topology() {
  echo "-Getting topology"
  echo "UDR pods distribution per worker " >$status_dir/topology.log
  for n in $(kubectl get node -o jsonpath='{range .items[*]}{..metadata.name}{"\n"}'); do
    echo "--------------------------------------------------------------------------------" >>$status_dir/topology.log
    echo $n >>$status_dir/topology.log
    echo "--------------------------------------------------------------------------------" >>$status_dir/topology.log
    kubectl describe node $n | grep "${namespace}" >>$status_dir/topology.log
  done
}
get_udr_zkcontent() {
  local udr_zkcontent_log_dir=$status_dir/udr_zk_content
  mkdir ${udr_zkcontent_log_dir}
  local PROV_POD=$(kubectl get pod -n "${namespace}" -l "app.kubernetes.io/name=eric-udr-system-status-provider" -o jsonpath='{.items[0].metadata.name}')
  local REQUEST="http://localhost:8080/udr-status/v1/tree?path=/udr\&recursive"
  command -v jq >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    kubectl exec -n "${namespace}" ${PROV_POD} -c eric-udr-system-status-provider -- bash -c "curl -s ${REQUEST}" | jq . >${udr_zkcontent_log_dir}/udr_zk_content.json
  else
    kubectl exec -n "${namespace}" ${PROV_POD} -c eric-udr-system-status-provider -- bash -c "curl -s ${REQUEST}" >${udr_zkcontent_log_dir}/udr_zk_content.json
  fi
}
siptls_logs() {
  echo "-Verifying for SIP-TLS logs-"
  local siptls_log_dir=$status_dir/sip_kms_dced
  local siptlsPods=$(kubectl -n "${namespace}" get pods | grep -i sip-tls | awk '{print $1}')
  if  [ -n "$siptlsPods" ]; then
    #echo "SIP-TLS Pods found, gathering sip-tls_logs.."
    mkdir ${siptls_log_dir}
    for i in $siptlsPods; do
      kubectl -n "${namespace}" exec $i -c sip-tls -- /bin/bash /sip-tls/sip-tls-alive.sh && echo $? >${siptls_log_dir}/alive_log_$i.out
      kubectl -n "${namespace}" exec $i -c sip-tls -- /bin/bash /sip-tls/sip-tls-ready.sh && echo $? >${siptls_log_dir}/ready_log_$i.out
      kubectl logs -n "${namespace}" $i -c sip-tls >${siptls_log_dir}/sip-tls_log_$i.json
      #To avoid to try to get logs from a non restarted pod
      if [ $(kubectl get pods -n ${namespace} $i -o jsonpath='{.status.containerStatuses[?(@.name == '\"sip-tls\"')].restartCount}') -ne 0 ];then
           kubectl logs -n "${namespace}" $i -c sip-tls --previous >${siptls_log_dir}/sip-tls-previous_log_$i.json
      fi
      kubectl -n "${namespace}" exec $i -c sip-tls -- env >${siptls_log_dir}/env_log_$i.out
    done
    kubectl --namespace ${namespace} exec eric-sec-key-management-main-0 -c kms -- bash -c 'vault status -tls-skip-verify' >${siptls_log_dir}/vault_status_kms.out
    kubectl --namespace ${namespace} exec eric-sec-key-management-main-0 -c shelter -- bash -c 'vault status -tls-skip-verify' >${siptls_log_dir}/vault_status_shelter.out
    kubectl get crd --namespace ${namespace} servercertificates.com.ericsson.sec.tls -o yaml >${siptls_log_dir}/servercertificates_crd.yaml
    kubectl get --namespace ${namespace} servercertificates -o yaml >${siptls_log_dir}/servercertificates.yaml
    kubectl get crd --namespace ${namespace} clientcertificates.com.ericsson.sec.tls -o yaml >${siptls_log_dir}/clientcertificates_crd.yaml
    kubectl get --namespace ${namespace} clientcertificates -o yaml >${siptls_log_dir}/clientcertificates.yaml
    kubectl get crd --namespace ${namespace} certificateauthorities.com.ericsson.sec.tls -o yaml >${siptls_log_dir}/certificateauthorities_crd.yaml
    kubectl get --namespace ${namespace} certificateauthorities -o yaml >${siptls_log_dir}/certificateauthorities.yaml
    kubectl get --namespace ${namespace} internalcertificates.siptls.sec.ericsson.com -o yaml >${siptls_log_dir}/internalcertificates.yaml
    kubectl get --namespace ${namespace} internalusercas.siptls.sec.ericsson.com -o yaml >${siptls_log_dir}/internalusercas.yaml
    kubectl get secret -n "${namespace}" -l com.ericsson.sec.tls/created-by=eric-sec-sip-tls >${siptls_log_dir}/secrets_created_by_eric_sip.out
    pod_name=$(kubectl get po -n "${namespace}" -l app=eric-sec-key-management -o jsonpath="{.items[0].metadata.name}")
    kubectl -n "${namespace}" exec $pod_name -c kms -- env VAULT_SKIP_VERIFY=true vault status >${siptls_log_dir}/kms_status_sip.out
    if [ "$(kubectl --namespace=${namespace} get pods | grep -i eric-sec-key-management-main-1)" ]; then
      echo "Gathering information to check split brain on KMS"
      mkdir ${siptls_log_dir}/KMS_splitbrain_check
      kmsspbr=${siptls_log_dir}/KMS_splitbrain_check
      kubectl exec --namespace ${namespace} eric-sec-key-management-main-0 -c kms -- bash -c "date;export VAULT_ADDR=http://localhost:8202;echo 'KMS-0';vault status -tls-skip-verify|grep 'HA Enabled' -A3" >${kmsspbr}/vault_Stat_HA.log
      kubectl exec --namespace ${namespace} eric-sec-key-management-main-1 -c kms -- bash -c "export VAULT_ADDR=http://localhost:8202;echo 'KMS-1';vault status -tls-skip-verify|grep 'HA Enabled' -A3" >>${kmsspbr}/vault_Stat_HA.log
      kubectl exec --namespace ${namespace} eric-sec-key-management-main-0 -c shelter -- bash -c "export VAULT_ADDR=http://localhost:8212;echo 'SHELTER-0';vault status -tls-skip-verify|grep 'HA Enabled' -A3" >>${kmsspbr}/vault_Stat_HA.log
      kubectl exec --namespace ${namespace} eric-sec-key-management-main-1 -c shelter -- bash -c "export VAULT_ADDR=http://localhost:8212;echo 'SHELTER-1';vault status -tls-skip-verify|grep 'HA Enabled' -A3" >>${kmsspbr}/vault_Stat_HA.log
      kubectl logs --namespace ${namespace} eric-sec-key-management-main-0 -c kms | grep -e "active operation" -e "standby mode" >>${kmsspbr}/active_operation.log
      kubectl logs --namespace ${namespace} eric-sec-key-management-main-1 -c kms | grep -e "active operation" -e "standby mode" >>${kmsspbr}/active_operation.log
      kubectl logs --namespace ${namespace} eric-sec-key-management-main-0 -c shelter | grep -e "active operation" -e "standby mode" >>${kmsspbr}/active_operation.log
      kubectl logs --namespace ${namespace} eric-sec-key-management-main-1 -c shelter | grep -e "active operation" -e "standby mode" >>${kmsspbr}/active_operation.log
    fi
  else
    echo "SIP-TLS Containers not found or not running, skipping..."
  fi
}
############### LOGS FUNCTIONS ##############################################
get_pods_logs() {
  echo "-Getting kubectl logs per POD-"
  kubectl -n "${namespace}" get pods | egrep "$PODFILTER" >${logs_dir}/kube_podstolog.txt
  for i in $(grep -v NAME ${logs_dir}/kube_podstolog.txt | awk '{print $1}'); do
    local pod_status=$(kubectl -n "${namespace}" get pod $i -o jsonpath='{.status.phase}')
    local pod_restarts=$(kubectl -n "${namespace}" get pod $i | grep -vi restarts | awk '{print $4}')
    for j in $(kubectl -n "${namespace}" get pod $i -o jsonpath='{.spec.containers[*].name}'); do
      kubectl -n "${namespace}" logs $i -c $j --since=$logs_interval >${logs_dir}/${i}_${j}.txt &
      if [[ "$pod_restarts" > "0" ]]; then
        kubectl -n "${namespace}" logs $i -c $j -p >${logs_dir}/${i}_${j}_prev.txt 2>/dev/null &
      fi
      # Only exec Pod in Running state
      if [[ "$pod_status" == "Running" ]]; then
        [ -d ${logs_dir}/env ] || mkdir ${logs_dir}/env
	#tap-agent container doesn't have bash shell
        [[ "$j" =~ "tap-agent" ]] || kubectl -n "${namespace}" exec $i -c $j -- env >${logs_dir}/env/${i}_${j}_env.txt &
      fi
    done
    
    local init_containers=$(kubectl -n "${namespace}" get pod $i -o jsonpath='{.spec.initContainers[*].name}')
    for j in $init_containers; do
      kubectl -n "${namespace}" logs $i -c $j --since=$logs_interval >${logs_dir}/${i}_${j}.txt &
      if [[ "$pod_restarts" > "0" ]]; then
        kubectl -n "${namespace}" logs $i -c $j -p >${logs_dir}/${i}_${j}_prev.txt 2>/dev/null &
      fi
    done
    while [ $(jobs | wc -l) -gt 10 ]; do
      sleep 3
    done
  done
  wait
}
logs_basic_checks () {
  local errDir=${logs_dir}/err
  local seDir=${logs_dir}/SE
  local dcedDir=${logs_dir}/sip_kms_dced/DCED
  mkdir ${errDir}
  mkdir ${seDir}
  mkdir -p ${dcedDir}
  echo "generate logs files with summary of error, latencies.."
  for i in $(ls ${logs_dir})
  do
    filename=$(echo $i| awk '{print substr($1,1,length($1)-4)}')
    log_path="${logs_dir}/$i"
    if ! [ -d $log_path ]; then
      cat ${log_path} | egrep -i "err|warn|crit" > ${errDir}/$filename.err.txt
      cat ${log_path} | egrep -i "failed to perform indices:data/write/bulk|latency|failed to send out heartbeat on time|disk|time out|timeout|timed out" > ${errDir}/$filename.latency.txt
    fi
  done
  
  pod_images_version_file= "${base_path}/info/describe/PODS/pods_image_versions.txt"
  echo "generate pod version list"
  if (($INFO)); then
    for i in $(ls ${base_path}/info/describe/PODS)
    do
      version=$(cat ${base_path}/info/describe/PODS/$i |grep "app.kubernetes.io/version")
      echo $i $version >> ${pod_images_version_file}
    done
  fi
  kubectl --namespace "${namespace}" top pods > ${logs_dir}/top_pod_output.txt
  kubectl --namespace "${namespace}" top node > ${logs_dir}/top_node_output.txt
  echo "get data-search-engine pod status"
  pod_status=$(kubectl --namespace ${namespace} get  pods | grep search-engine|wc -l)
  if [[ "$pod_status" > "0" ]]; then
    esRest="kubectl -n ${namespace} exec -c ingest $(kubectl get pods -n ${namespace} -l "app=eric-data-search-engine,role in (ingest-tls,ingest)" -o jsonpath="{.items[0].metadata.name}") -- /bin/esRest"
    $esRest GET /_cat/nodes?v > ${seDir}/nodes.txt
    $esRest GET /_cat/indices?v > ${seDir}/indices.txt
    $esRest GET /_cluster/health?pretty > ${seDir}/health.txt
    $esRest GET /_cluster/allocation/explain?pretty > ${seDir}/allocation.txt
  fi
   echo "get_ddced_data"
   for i in `kubectl --namespace "${namespace}" get pod |grep data-distributed-coordinator-ed|grep -v agent|awk '{print $1}'`
   do
           kubectl --namespace "${namespace}" exec $i -c dced -- etcdctl member list -w fields >  ${dcedDir}/memberlist_$i.txt
           kubectl --namespace "${namespace}" exec $i -c dced -- bash  -c 'ls /data/member/snap -lh' >  ${dcedDir}/sizedb_$i.txt
           kubectl --namespace "${namespace}" exec $i -c dced -- bash  -c 'du -sh data/*;du -sh data/member/*;du -sh data/member/snap/db' >>  ${dcedDir}/sizedb_$i.txt
#           kubectl --namespace "${namespace}" exec $i -c dced -- etcdctl  endpoint status --endpoints=:2379 --insecure-skip-tls-verify=true -w fields>  ${dcedDir}/endpoints_$i.txt
           kubectl --namespace "${namespace}" exec $i -c dced -- bash -c 'unset ETCDCTL_ENDPOINTS; etcdctl endpoint status --endpoints=:2379 --insecure-skip-tls-verify=true -w fields'> ${dcedDir}/endpoints_$i.txt
           kubectl --namespace "${namespace}" exec $i -c dced -- etcdctl user list --insecure-skip-tls-verify >  ${dcedDir}/user_list$i.txt
   done
}
sm_log() {
    #echo "-----------------------------------------"
    echo "-Verifying for SM logs -"
    #echo "-----------------------------------------"
  
    local sm_log_dir=${logs_dir}/sm_log
    local serviceMeshCustomResources=("adapters.config" "attributemanifests.config" "authorizationpolicies.security" "destinationrules.networking" "envoyfilters.networking" "gateways.networking" "handlers.config" "httpapispecbindings.config" "httpapispecs.config" "instances.config" "peerauthentications.security" "proxyconfigs.networking" "quotaspecbindings.config" "quotaspecs.config" "rbacconfigs.rbac" "requestauthentications.security" "rules.config" "serviceentries.networking" "servicerolebindings.rbac" "serviceroles.rbac" "sidecars.networking" "telemetries.telemetry" "templates.config" "virtualservices.networking" "wasmplugins.extensions" "workloadentries.networking" "workloadgroups.networking")
    local istioDebugURL=("adsz" "syncz" "registryz" "endpointz" "instancesz" "endpointShardz" "configz" "cachez" "resourcesz" "authorizationz" "push_status" "inject" "mesh" "networkz")
    local proxyDebugURL=("certs" "clusters" "config_dump?include_eds" "listeners" "memory" "server_info" "stats/prometheus" "runtime")
  if [ "$(kubectl --namespace "${namespace}" get pods --selector app=istiod | grep eric-mesh-controller | grep Running)" ]
  then
    mkdir -p ${sm_log_dir}/istio
    #echo "SM Controller pods found running, gathering sm_log for controller pods..."
    for pod_name in `kubectl --namespace "${namespace}" get pods --selector app=istiod --no-headers | awk -F " " '{print $1}'`
      do
        mkdir -p ${sm_log_dir}/istio/$pod_name/debug
        for debug_path in ${istioDebugURL[@]}
          do
            kubectl --namespace "${namespace}" exec ${pod_name} -c discovery -- curl --silent http://localhost:15014/debug/${debug_path} > ${sm_log_dir}/istio/${pod_name}/debug/${debug_path}.json
          done
      done
    if (kubectl --namespace "${namespace}" get crd | grep istio.io >/dev/null)
    then
      #echo "SM Controller CRDs have been found, looking for applied CRs..."
      for sm_crs in `kubectl --namespace "${namespace}" get crd | grep istio.io |awk '{print $1}'`
        do
          if [[ $(kubectl --namespace "${namespace}" get ${sm_crs} --ignore-not-found) ]]
          then
            local sm_cr=$(echo ${sm_crs} | awk -F "." '{print $1}')
            mkdir -p ${sm_log_dir}/ServiceMeshCRs/${sm_cr}
            echo "Applied ${sm_cr} CR has been found, gathering sm_log for it..."
            for resource in `kubectl --namespace "${namespace}" get ${sm_crs} --no-headers | awk -F " " '{print $1}'`
              do 
                kubectl --namespace "${namespace}" get ${sm_crs} ${resource} -o yaml > ${sm_log_dir}/ServiceMeshCRs/${sm_cr}/${resource}.yaml
              done
          fi
        done
    else
      echo "No SM Controller CRD has been found!"
    fi
    if [ "$(kubectl --namespace "${namespace}" get pods -o jsonpath='{.items[*].spec.containers[*].name}' | grep istio-proxy)" ]
    then
      mkdir -p ${sm_log_dir}/proxies
      echo "Pods with istio-proxy container are found, gathering sm_log for pods with istio-proxy..."
      for pod_name in `kubectl --namespace="${namespace}" get pods -o jsonpath='{range .items[*]}{"\n"}{.metadata.name}{": "}{range .spec.containers[*]}{.name}{" "}{end}{end}' | grep istio-proxy | awk -F ":" '{print $1}'`
        do  
          mkdir ${sm_log_dir}/proxies/${pod_name}
          for debug_path in ${proxyDebugURL[@]}
            do
              if [[ ${debug_path} == "stats/prometheus" ]]; then
                mkdir ${sm_log_dir}/proxies/${pod_name}/stats
              fi
              kubectl --namespace "${namespace}" exec ${pod_name} -c istio-proxy -- curl --silent http://localhost:15000/${debug_path} > ${sm_log_dir}/proxies/${pod_name}/${debug_path}.json
            done
        done
    else
      echo "Pods with istio-proxy containers are not found or not running, doing nothing"
    fi
  else
    echo "ServiceMesh Controller pods are not found or not running, doing nothing"
  fi
}
get_ss7_cnf() {
  if (kubectl --namespace="${namespace}" get pods | grep -i ss7); then
    for i in $(kubectl --namespace "${namespace}" get pod -o json | jq -r '.items[] | select(.spec.containers[].name=="ss7") | .metadata.name'); do
      cnfpath="${log_base_path}"/ss7_cnf_$i
      mkdir $cnfpath
      kubectl --namespace "$namespace" cp $i:/opt/cnf-dir/ -c ss7 ${cnfpath} > /dev/null
    done
  fi
}
############### LOGS ES FUNCTIONS ##############################################
get_logs_elastic() {
  echo "-Getting ElasticSearch logs-"
  local esLogsPath=${base_path}/logs/ElasticSearch
  mkdir -p $esLogsPath
  # get container pod n_logs
  local logs_list="${esLogsPath}/list_logs_by_pod_and_container.txt"
  local tmp_list="${esLogsPath}/tmp_list_logs_by_pod_and_container.txt"
  get_log_number_by_pod_and_container ${tmp_list}
  # apply filters to pods and containers
  egrep "${CNTRFILTER}" ${tmp_list} | egrep "${PODFILTER}" > ${logs_list}
  cat ${logs_list}
  rm ${tmp_list}
  # get logs from filtered list
  echo "Getting logs from datasearch-engine for each pod_container element of the list from ${time_start_iso} to ${time_end_iso}"
  while IFS= read -r line; do
    local kubernetes_pod_name=$(echo $line | awk '{print $1}')
    local kubernetes_container_name=$(echo $line | awk '{print $2}')
    local kubernetes_pod_log_number=$(echo $line | awk '{print $3}')
    get_individual_log_filter_pod_and_container $kubernetes_pod_name $kubernetes_container_name $kubernetes_pod_log_number
  done < $logs_list
}
get_individual_log_filter_pod_and_container() {
  local kubernetes_pod_name=$1
  local kubernetes_container_name=$2
  local kubernetes_pod_log_number=$3
  local identifier="${kubernetes_pod_name}_${kubernetes_container_name}"
  local output_file="$esLogsPath/${identifier}.txt"
  
  local tmp_json_output="$esLogsPath/.tmp.json"
  local searchEngine="eric-data-search-engine-data-0"
  local target="/*/_search?size=10000&pretty"
  local search_ts="\"$time_start_iso\""
  while [ ${kubernetes_pod_log_number} -gt 0 ]; do
    local query="{
      \"_source\":  [
          \"message\",
          \"severity\",
          \"timestamp\"
      ],
      \"sort\": [
        {\"@timestamp\": {\"order\": \"asc\"}}
      ],
      \"search_after\": [
        ${search_ts}
      ],
      \"query\": {
        \"bool\": {
          \"must\": [
              {\"term\": {\"kubernetes.pod.name.keyword\": \"${kubernetes_pod_name}\" }},
              {\"term\": {\"kubernetes.container.name.keyword\": \"${kubernetes_container_name}\" }}
          ],
          \"filter\": [
            {
              \"range\": {
                \"timestamp\": {
                    \"time_zone\": \"+00:00\",
                    \"gte\": \"${time_start_iso}\",
                    \"lte\": \"${time_end_iso}\"
                }
              }
            }
          ]
        }
      }
    }"
    kubectl exec -n "${namespace}" $searchEngine -c data -- /bin/esRest GET $target -H 'Content-Type: application/json' -d "$query" > ${tmp_json_output}
    # echo "kubectl exec -n \"${namespace}\" $searchEngine -c data -- /bin/esRest GET $target -H 'Content-Type: application/json' -d \"$query\""  
    # get last timestamp we got so we can search after that
    search_ts=$(jq '.hits.hits[-1]._source.timestamp' ${tmp_json_output})
    # parse current contents to output file
    jq '.hits.hits[]._source  | {timestamp, severity, message}|join(" ")' ${tmp_json_output} >> "${output_file}"
    kubernetes_pod_log_number=$(($kubernetes_pod_log_number - 10000))
  done
  rm ${tmp_json_output}
}
get_log_number_by_pod_and_container() {
  output_file="$1"
  echo "Getting logs from datasearch-engine for each pod and container  from ${time_start_iso} to ${time_end_iso}"
  echo "-Getting logs count from ElasticSearch-"
  local searchEngine="eric-data-search-engine-data-0"
  local indexDate=$(date +%F -d "${time_start_iso}" | sed 's/-/./g')
  local target="*"
  local target="/${target}/_search?size=10000&pretty"
  local query="{
    \"_source\": {
        \"includes\": [
            \"kubernetes.pod.name\",
            \"kubernetes.container.name\",
            \"timestamp\"
        ]
    },
    \"query\": {
        \"bool\": {
            \"filter\": {
                \"range\": {
                    \"timestamp\": {
                        \"time_zone\": \"+00:00\",
                        \"gte\": \"${time_start_iso}\",
                        \"lte\": \"${time_end_iso}\"
                    }
                }
            }
        }
    },
  \"aggs\": {
    \"pods_that_logged\": {
      \"terms\": {
        \"field\": \"kubernetes.pod.name.keyword\",
        \"order\": {
          \"_count\": \"asc\"
        },
        \"size\": 2000
      },
      \"aggs\": {
        \"containers_that_logged\": {
          \"terms\": {
            \"field\": \"kubernetes.container.name.keyword\",
            \"order\": {
              \"_count\": \"asc\"
            },
          \"size\": 2000
          }
        }
      }
    }
  }
}"
  kubectl exec -n "${namespace}" -i ${searchEngine} -c data -- /bin/esRest GET "${target}" -H 'Content-Type: application/json' --data-binary "${query}" | jq '.aggregations.pods_that_logged.buckets[] | .key as $pod_name | (.containers_that_logged).buckets[] | {pod_name: $pod_name, container_name: .key, num_log_line: (.doc_count|tostring)} | join(":")' | sed s/\"//g | column -s ":" -t > ${output_file}
}
############### ESREST FUNCTIONS ##############################################
get_es_logs() {
  echo "-Getting ElasticSearch logs-"
  local esLogsPath=${base_path}/logs/ElasticSearch
  mkdir -p ${esLogsPath}
  local searchEngine="eric-data-search-engine-data-0"
  local target="/*/_search?size=10000&pretty"
  local search_ts="\"$time_start_iso\""
  local retrieved_log_entries=10000   #Begin with the possible maximum
  local tmp_json_output="$esLogsPath/.tmp.json"
  local output_file="${esLogsPath}/logs_es.log"
  while [ ${retrieved_log_entries} -gt 0 ]; do
    regex="`echo $PODFILTER | sed 's/|/*|/g'`*"
   # echo $regex
    local query="{
      \"_source\": {
          \"includes\": [
              \"message\",
              \"severity\",
              \"kubernetes.pod.name\",
	      \"kubernetes.container.name\",
              \"timestamp\"
          ]
      },
      \"sort\": [{\"timestamp\": {\"order\": \"asc\"}}],
        \"search_after\": [
          ${search_ts}
        ],
      \"query\": { \"bool\":{ \"must\": {
          \"simple_query_string\":{
             \"query\": \"${regex}\",
             \"fields\": [\"kubernetes.pod.name\"],
             \"analyze_wildcard\":true,
             \"default_operator\":\"AND\"
          }},
          \"filter\": {
            \"range\": {
              \"timestamp\": {
    	        \"time_zone\": \"+00:00\",
                \"gte\": \"${time_start_iso}\",
                \"lte\": \"${time_end_iso}\"
              }
            }
          }
        }
      }
    }"
    #echo ${query} 
    kubectl exec -n "${namespace}" ${searchEngine} -c data -- /bin/esRest GET ${target} -H 'Content-Type: application/json' --data-binary "${query}" > ${tmp_json_output}
    # get last timestamp we got so we can search after that
    search_ts=$(jq '.hits.hits[-1]._source.timestamp' ${tmp_json_output})
    # parse current contents to output file
    jq '.hits.hits[]._source  | {timestamp, pod_name: .kubernetes.pod.name, contaner_name: .kubernetes.container.name, severity, message} |join(" ")' ${tmp_json_output} >> "${output_file}"
    retrieved_log_entries=$(jq '.hits.total.value' ${tmp_json_output})
  done
  rm ${tmp_json_output}
cat ${esLogsPath}/logs_es.log
}
############### COUNTERS FUNCTIONS ##############################################
get_counter_labels() {
  local service="${1%%.*}"
  local outputfile="$2"
  local counter_ns="${3:-$namespace}"
  local PROV_POD=$(kubectl -n "${namespace}" get pod -l "app.kubernetes.io/name=eric-udr-system-status-provider" -o jsonpath='{.items[0].metadata.name}')
  
  kubectl -n "${counter_ns}" exec -i "${service}-0" -c eric-pm-server -- promtool query labels http://localhost:9090 __name__  > "${outputfile}"
}
get_counter_values() {
  local service="${1%%.*}"
  local QUERY="$2"
  local counter_ns="$3"
  echo "kubectl -n "${counter_ns}" exec -i ${service}-0 -c eric-pm-server -- promtool query range http://localhost:9090 ${QUERY} --start=${time_start_epoch_sec} --end=${time_end_epoch_sec} --step=${rate_interval} -o json | jq .[]" >>"${queries_executed_file}"
  kubectl -n "${counter_ns}" exec -i "${service}-0" -c eric-pm-server -- promtool query range http://localhost:9090 ${QUERY} --start=${time_start_epoch_sec} --end=${time_end_epoch_sec} --step=${rate_interval} -o json | jq .[] 2>/dev/null   
}
get_metrics_blocks() {
  local service="$1"
  local counters_list="$(egrep "$LABELFILTER" $2)"
  local destDirectory="${metrics_log_dir}/${service/%\.monitoring*/-monitoring}"
  local counter_ns="${3:-$namespace}"
  local queries_executed_file="${metrics_log_dir}/queries-executed-${service/%\.monitoring*/-monitoring}.txt"
  echo "--All queries executed to get counters will be logged in ${queries_executed_file}"
  echo " --init $(date) Start getting counters from: ${service}"
  mkdir -p ${destDirectory}
  for counter_name in ${counters_list}; do
    local normal_counter_name="$(echo ${counter_name} | sed 's/:/-/g').json"
    local query_var="${counter_name}"
    local outputfile="$destDirectory/$normal_counter_name" 
    while [ $(jobs | wc -l) -gt 10 ]; do
      sleep 3
    done
    get_counter_values "${service}" "${query_var}" "${counter_ns}" >${outputfile} &
  done
  wait
}
get_counters() {
  local initial_time="$(date -u +%s)"
  local metrics_log_dir="${base_path}/udr_metrics"
  mkdir ${metrics_log_dir}
  local pm_labels_file="${metrics_log_dir}/labels-prometheus-split-in-lines.txt"
  local pm_service="eric-pm-server"
  get_counter_labels "${pm_service}" "${pm_labels_file}"
  echo "  GETTING METRICS CAN TAKE UP TO 15 minutes. Some will get in background in parallel and can load a bit the host where the script is run"
  get_metrics_blocks "${pm_service}" "${pm_labels_file}"
  local final_time="$(date -u +%s)"
  echo "Got Counters in $(($final_time - $initial_time)) seconds"
}
get_monitoring_counters() {
  local initial_time="$(date -u +%s)"
  local metrics_log_dir="${base_path}/udr_metrics"
  mkdir ${metrics_log_dir}
  local pm_monitoring_external_labels_file="${metrics_log_dir}/labels-prometheus-monitoring-external-split-in-lines.txt"
  local pm_monitoring_external_service="eric-pm-server-external.monitoring.svc.cluster.local"
  get_counter_labels "${pm_monitoring_external_service}" "${pm_monitoring_external_labels_file}" "monitoring"
  echo "  GETTING METRICS CAN TAKE UP TO 15 MINUTES. Some will get in background in parallel and can load a bit the host where the script is run"
  get_metrics_blocks "${pm_monitoring_external_service}" "${pm_monitoring_external_labels_file}" "monitoring"
  local final_time="$(date -u +%s)"
  echo "Got Monitoring Counters in $(($final_time - $initial_time)) seconds"
}
############### KVDB FUNCTIONS ##############################################
get_kvdb_stats_logs() {
  [ -z "$1" ] && echo -e "\e[1;31mError:\e[0m Expected arg for kvdb: stats/logs"  
  local option=$1
  local kvdb_dir="${base_path}/kvdb_${option}"
  if [[ -z $PODFILTER || "$PODFILTER" == "all" ]]; then
    num_kvdb_serv=$(kubectl -n "${namespace}" get pods |grep eric-udr-kvdb-ag-server | wc -l)
    kvdb_pods=$(seq 0 $(($num_kvdb_serv -1 )))
  else
    IFS='|' read -ra kvdb_pods <<< "$PODFILTER"
  fi
  for pod_id in ${kvdb_pods[@]}; do
    local pod="eric-udr-kvdb-ag-server-${pod_id}"
    local pod_dir="${kvdb_dir}/${pod}"
    mkdir -p $pod_dir 
    local files_to_get=($(kubectl exec -n "${namespace}" -i -c eric-udr-kvdb-ag-server ${pod} -- ls -t ${option} | egrep "^eric.+(log|gz)$"))
    local n_files=$((${#files_to_get[@]}-1))
    if [[ -n "$NFILES" && "$NFILES" != "all" ]]; then
      n_files=$(($NFILES-1 < $n_files ? $NFILES-1 : $n_files))
    fi
      for i in $(seq 0 $n_files); do
        local file=${files_to_get[$i]}
        echo "Getting ${pod}:${option}/${file}"
        kubectl -n "${namespace}" cp -c eric-udr-kvdb-ag-server ${pod}:${option}/${file} ${pod_dir}/${file} > /dev/null
      done
  done
}
############### GLOBAL FUNCTIONS ############################################
set_query_interval() {
  # Set default values for the options if not set
  time_start=${time_start_arg:-"2 hour ago"}
  time_end=${time_end_arg:-"now"}
  #Time variables will be used while executing the queries in get_counter_values() function"
  time_start_epoch_sec=$(date +%s -d "$time_start")
  time_end_epoch_sec=$(date +%s -d "$time_end")
  # ISO format
  time_start_iso=$(date -Iseconds -d "${time_start}" | sed 's/+.*//i')
  time_end_iso=$(date -Iseconds -d "${time_end}" | sed 's/+.*//i')
  # set interval used in log obtention queries 
  if [ -n "$time_start_arg" ]; then
    logs_interval="$(($(date +%s -d "now") - ${time_start_epoch_sec}))s"
  else
    logs_interval=0
  fi
  # rate interval used for counters
  rate_interval="30s"
  # set interval used in counter obtention queries
  time_interval="$((${time_end_epoch_sec} - ${time_start_epoch_sec}))s"
  echo -e "\n-Using time interval: Start Time $time_start_iso -- End Time $time_end_iso)  - Total time: $time_interval"
}
get_status() {
  initial_time="$(date -u +%s)"
  status_dir="${base_path}/status"
  mkdir $status_dir
  get_events &
  get_geode_info &
  get_pods_ips_status &
  get_udr_alarms &
  get_udr_connections &
  get_udr_system_status &
  get_udr_topology &
  get_udr_zkcontent &
  siptls_logs & 
  wait
  final_time="$(date -u +%s)"
  echo "Got Status in $(($final_time - $initial_time)) seconds"
}
get_info() {
  initial_time="$(date -u +%s)"
  info_dir="${base_path}/info"
  mkdir $info_dir
  get_cluster_inventory &
  get_cluster_resources &
  #To avoid perl error while executing from the director executed without &
  get_envoy_config 
  get_helm_info &
  get_http_proxy_config &
  get_istio_config &
  get_kafka_info &
  get_prom_info &
  get_udr_config &
  cmm_collect_logs &
  cmy_log &
  #Redirection to /dev/null added due printout while the reosurces doesn't exists that couldn't remove
  get_describe_info 2> /dev/null
  wait
  final_time="$(date -u +%s)"
  echo "Got Info in $(($final_time - $initial_time)) seconds"
}
get_logs_kubectl() {
  initial_time="$(date -u +%s)"
  logs_dir="${base_path}/logs"
  mkdir -p $logs_dir
  get_pods_logs &
  wait
  final_time="$(date -u +%s)"
  echo "Got Logs in $(($final_time - $initial_time)) seconds"
}
get_logs_extra_content_adp() {
  logs_dir="${base_path}/logs"
  mkdir -p $logs_dir
  get_ss7_cnf &
  sm_log &
  wait
  logs_basic_checks      
}
get_all_data() {
  get_counters &
  get_logs_kubectl &
  get_logs_extra_content_adp &  
  get_status &
  get_info &   
  wait
}
gen_exec_report() {
  echo -e "Collect UDR Info report:\nDate: $(date +"%D %T")\nVersion: $VERSION" >$base_path/ticket.txt
  if [ $KVDB -ne 0 ]; then
     (($STATUS)) && echo "Got KVDB status" >> $base_path/ticket.txt
     (($LOGS)) && echo "Got KVDB logs" >> $base_path/ticket.txt
     [ -n "$PODFILTER" ] && echo "- Filtered pods with regex: eric-udr-kvdb-ag-server-[$PODFILTER]" >> $base_path/ticket.txt
     [ -n "$NFILES" ] && echo "- Obtained last $NFILES files" >> $base_path/ticket.txt
  elif [ $ESREST -ne 0 ]; then
    echo "Got system logs with esRest " >> $base_path/ticket.txt
    [ -n "$PODFILTER" ] && echo " -Filtered esRest pod logs with regex: [$PODFILTER]" >> $base_path/ticket.txt
    [ -n "$CNTRFILTER" ] && echo "- Filtered containers with regex: [$CNTRFILTER]" >> $base_path/ticket.txt
  else
    (($STATUS)) && echo "Got system status" >> $base_path/ticket.txt
    (($INFO)) && echo "Got system info" >> $base_path/ticket.txt
    (($COUNTERS)) && echo "Got $namespace counters" >> $base_path/ticket.txt
    [ -n "$LABELFILTER" ] && echo "- Filtered counters with regex: [$LABELFILTER]" >> $base_path/ticket.txt
    (($MON)) && echo "Got monitoring counters" >> $base_path/ticket.txt
    if [ $LOGS -ne 0 ]; then
      if [ $ESLOGS -ne 0 ]; then
        echo "Got system logs from ElasticSearch" >> $base_path/ticket.txt
        [ -n "$CNTRFILTER" ] && echo "- Filtered containers with regex: [$CNTRFILTER]" >> $base_path/ticket.txt
      else
        echo "Got system logs with kubectl" >> $base_path/ticket.txt
        [ -n "$PODFILTER" ] && echo "Filtered pod logs with regex: [$PODFILTER]" >> $base_path/ticket.txt
      fi
    fi
  fi
}
command -v jq &>/dev/null
if [ $? -eq 1 ]; then
  echo ""
  echo "+++++++++++++++++++++++++++ WARNING !!! ++++++++++++++++++++++++++++++++++++++++"
  echo "+++++++ Utility jq not found in your system, JSON output won't be pretty +++++++"
  echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  echo ""
fi
# Define date options format
date_input_format="\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)"
date_format="\1-\2-\3 \4:\5:\6"
#Parse arguments
ARGS=$(getopt -o s:e:f:b:n:p:climtrkhv --long start:,end:,filterContainers:,filterCounters:,filterPods:,nfiles:,counters,logs,info,monitoring,status,esrest,adp,kvdb,elastic,help,version -n $0 -- "$@" 2>/dev/null)
if [ $? != 0 ]; then
  echo -e "\e[1;31mError:\e[0m Unsupported flag \"$1\""
  printUsage
  exit 1
fi
OPT=0
MON=0
KVDB=0
ESREST=0
ESLOGS=0
LOGS=0
ADPLOGS=0
eval set -- "$ARGS"
while true; do
  case "$1" in
  -s | --start)
    time_start_arg="$2"
    time_start_arg=$(echo "$time_start_arg" | sed -e "s/"$date_input_format"/$date_format/")
    shift
    ;;
  -e | --end)
    time_end_arg="$2"
    time_end_arg=$(echo "$time_end_arg" | sed -e "s/"$date_input_format"/$date_format/")
    shift
    ;;
  -f | --filterCounters)
    LABELFILTER="$2"
    shift
    ;;
  -b | --filterContainers)
    CNTRFILTER="$2"
    shift
    ;;
  -n | --nfiles)
    NFILES="$2"
    shift
    ;;
  -p | --filterPods)
    PODFILTER="$2"
    shift
    ;;
  -c | --counters)
    COUNTERS=1
    OPT=1
    ;;
  -m | --monitoring)
    MON=1
    OPT=1
    ;;
  -l | --logs)
    LOGS=1
    OPT=1
    ;;
  --elastic)
    ESLOGS=1
    ;;
  --adp)
    ADPLOGS=1
    ;;
  -i | --info)
    INFO=1
    OPT=1
    ;;
  -t | --status)
    STATUS=1
    OPT=1
    ;;
  -r | --esrest)
    ESREST=1
    ;;
  -k | --kvdb)
    KVDB=1
    ;;
  -h | --help)
    printUsage
    exit 0
    ;;
  -v | --version)
    echo "Collect_UDR_info version: $VERSION"
    exit 0
    ;;
  --)
    shift
    break
    ;;
  *)
    echo -e "\e[1;31mError:\e[0m Unsupported flag \"$1\""
    printUsage
    exit 1
    ;;
  esac
  shift
done
set_query_interval
# if no namespace provided use the default one
if [ -n "$1" ]; then
  namespace="$1"
  echo "Using namespace: \"$namespace\" received as parameter"
else
  default_namespace="$(kubectl config view --minify --output jsonpath='{.contexts[].context.namespace}')"
  if [ -n "$default_namespace" ]; then
    namespace="$default_namespace"
    echo "Using namespace: \"$namespace\" DEFAULT namespace from kubeconfig"
  else
    ccdm_namespace="$(helm list -A -o json | jq '.[] | select( .chart | contains("eric-ccdm-service-mesh-"))' | jq -r .namespace)"
    if [ -n "$ccdm_namespace" ]; then
      namespace="$ccdm_namespace"
      echo "Using namespace: \"$namespace\" from helm namespace where is installed eric-ccdm-service-mesh"
    else
      echo "\e[1;31mError:\e[0m couldn't detect namespace, exitting..."
      exit 1
    fi
  fi
fi
if [ $(kubectl -n "${namespace}" get pods 2>/dev/null | wc -l) -eq 0 ]; then
  echo -e "\e[1;31mError:\e[0m No pods found in \"${namespace:-$default_namespace}\" namespace"
  exit 1
fi
# Create output directory
base_dir="data_collection_${namespace}_$(date "+%Y-%m-%d-%H-%M-%S")"
echo "All files will be stored under ${base_dir}"
if [ $KVDB -ne 0 ]; then
  base_dir+="_kvdb-data"
  if [ $OPT -ne 0 ]; then
    (($LOGS)) && base_dir+="-logs"
    (($STATUS)) && base_dir+="-stats"
  else
    base_dir+="-all"
  fi
elif [ $ESREST -ne 0 ]; then
  base_dir+="_rest"
elif [ $OPT -ne 0 ]; then
  (($COUNTERS)) && base_dir+="_counters"
  (($MON)) && base_dir+="_monitoring-counters"
  if [ $LOGS -ne 0 ]; then
    if [ $ESLOGS -ne 0 ]; then
      base_dir+="_es-logs"
    else
      base_dir+="_logs"
      if [ $ADPLOGS -ne 0 ]; then
        base_dir+="-adp"
      fi
    fi
  fi
  (($STATUS)) && base_dir+="_stats"
  (($INFO)) && base_dir+="_info"
else
  base_dir+="_ALL"
fi
# create base directory 
base_path="$PWD/${base_dir}"
mkdir ${base_dir}
# exec tasks
initial_time=$(date)
gen_exec_report
if [ $KVDB -ne 0 ]; then
  if [ $OPT -ne 0 ]; then
    (($LOGS)) && get_kvdb_stats_logs "logs" &
    (($STATUS)) && get_kvdb_stats_logs "stats" &
  else
    get_kvdb_stats_logs "logs" &
    get_kvdb_stats_logs "stats" &
  fi
elif [ $ESREST -ne 0 ]; then
  get_es_logs &
elif [ $OPT -ne 0 ]; then
  if [ $LOGS -ne 0 ]; then
    if [ $ESLOGS -ne 0 ]; then
      get_logs_elastic &
    else
      get_logs_kubectl &
      if [ $ADPLOGS -ne 0 ]; then
        get_logs_extra_content_adp &
      fi
    fi
  fi
  (($COUNTERS)) && get_counters &
  (($MON)) && get_monitoring_counters &
  (($STATUS)) && get_status &
  (($INFO)) && get_info &
else
  get_all_data
fi
wait
find $base_dir -type f -empty -delete
compress_files
final_time=$(date)
echo "Data collection finished: start_time=${initial_time} end_time=${final_time}"
exit 0
