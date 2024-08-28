#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Auther: ken.shi@ericsson.com
# ----------------------------------------------------------------------------

help()
{
    echo "Usage: check_evenness.sh -n 10"
    echo "       check_evenness.sh -c n28-eccd1 -n 10"
    exit 1
}

print_uneven_spread_pods()
{
    nworker=$1
    kubeconfig_options=$2

    echo "----------------------------------"
    echo "List unevenly spreaded replicasets"
    echo "----------------------------------"
    echo -e "NAMESPACE\tReplicaSets"
    
    for type in replicaset statefulset
    do
        all_info=$(kubectl ${kubeconfig_options} get $type --all-namespaces -o json | jq '[.items[] | select(.spec.replicas>=2) | {ns:.metadata.namespace,name:.metadata.name,replicas:.spec.replicas}]')
    
        for ns in $(echo ${all_info} | jq -r .[].ns | sort | uniq)
        do
            ns_replica_info=$(echo ${all_info} | jq --arg ns "$ns" '[.[] | select(.ns==$ns)]')
            for replicaset in $(echo ${ns_replica_info} | jq -r .[].name)
            do
                replica=$(echo ${ns_replica_info} | jq --arg replicaset "$replicaset" '.[] | select(.name==$replicaset)| .replicas')
                installed_nworker=$(kubectl ${kubeconfig_options} -n $ns get pod -o wide | grep $replicaset | awk '{print $7}' | sort | uniq | wc -l)
                if ([[ ${installed_nworker} -lt $replica ]] && [[ replica -le $nworker ]]) || ([[ ${installed_nworker} -lt $nworker ]] && [[ replica -gt $nworker ]])
                then
                    echo -e $ns'\t\t'$replicaset
                fi
            done
        done
    done
}

while getopts 'c:n:h' OPT; do
    case $OPT in
        c) cluster="$OPTARG";;
        n) numberOfWorker="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done

script_dir="$(dirname $(readlink -f "$0"))"
kubeconfig_dir="${script_dir}/kubeconfig"

if [[ -z ${cluster} ]]; then
    kubeconfig_options=''
else
    kubeconfig_options="--kubeconfig=${kubeconfig_dir}/${cluster}.config"
fi

print_uneven_spread_pods "${numberOfWorker}" "${kubeconfig_options}" 
