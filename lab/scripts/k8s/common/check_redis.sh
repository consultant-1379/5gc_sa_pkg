#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Auther: ken.shi@ericsson.com
# ----------------------------------------------------------------------------

help()
{
    echo "Description:"
    echo " This script checks the kvdb/redis master/slave distribution in the cluster."
    echo "Usage:"
    echo " Running on terminal server: check_redis.sh -c <cluster> -n <namespace>"
    echo " Running on cluster:          check_redis.sh -n <namespace>"
    exit 1
}

function get_redis_status()
{
  redispods=$(kubectl ${kubeconfig_options} -n ${namespace} get pod -o wide | grep kvdb-rd-server | awk '{print $1}')
  local results=$(for pod in ${redispods}
  do
    redis_info=$(kubectl ${kubeconfig_options} -n ${namespace} exec -i $pod -c eric-pc-kvdb-rd-server -- redis-cli info replication)
    worker=$(kubectl ${kubeconfig_options} -n ${namespace} get pod -o wide | grep ${pod} | awk '{print $7}')
    echo -ne "${namespace}\t"
    echo -ne "${worker}\t"
    echo -ne "${pod}\t"
    role=$(echo "${redis_info}" | grep role | cut -d: -f2 | tr -d '\r')
    echo -n ${role}
    echo -ne '\t'
    if [[ ${role} == "master" ]]; then
        peer_ip=$(echo "${redis_info}" | grep "slave0" | cut -d, -f1 | cut -d= -f2 | tr -d '\r')
        peer_slave=$(kubectl ${kubeconfig_options} -n ${namespace} get pod -o wide | grep ${peer_ip} | grep kvdb-rd-server | awk '{print $1}')
        echo ${peer_slave}
    elif [[ ${role} == "slave" ]]; then
        peer_ip=$(echo "${redis_info}" | grep "master_host" | cut -d: -f2 | tr -d '\r')
        peer_master=$(kubectl ${kubeconfig_options} -n ${namespace} get pod -o wide | grep ${peer_ip} | grep kvdb-rd-server | awk '{print $1}')
        echo ${peer_master}
    fi
  done | sort -k3 | sort -k1)
  echo "$results"

}


while getopts 'c:n:h' OPT; do
    case $OPT in
        c) cluster="$OPTARG";;
        n) namespaces="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done

kubeconfig_dir="/lab/pccc_utils/scripts/src/kubeconfig"

if [[ -z ${cluster} ]]; then
    kubeconfig_options=''
else
    kubeconfig_options="--kubeconfig=${kubeconfig_dir}/${cluster}.config"
fi
results=$(for namespace in $(echo $namespaces | sed 's/,/ /g' |  awk '{print $0}')
do
  get_redis_status &
done
wait
)
echo -e "namespace\tworker\t\t\t\tredis_pod_name\t\t\trole\tpeer_redis_pod"
echo "------------------------------------------------------------------------------------------------------"
echo "$results"

