#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Auther: ken.shi@ericsson.com
# ----------------------------------------------------------------------------

help()
{
    echo "Usage: check_resources_allocation.sh [ -c cluster ] [ -k cluster ] [ -n namespace ]"
    echo "Warning: Recommend to use '-k' option, '-c' will be deprecated"
    echo "Examples:"
    echo "  check_resources_allocation.sh"
    echo "  check_resources_allocation.sh -k n99-eccd1"
    echo "  check_resources_allocation.sh -k n99-eccd1"
    echo "  check_resources_allocation.sh -k n99-eccd1 -n pcc"
    echo "  check_resources_allocation.sh -k n99-eccd1 -n \"pcc pcg\""
    exit 1
}

print_resource_allocation()
{
    kubeconfig_options=$1
    ns_list=$2

    sum_cluster_cpu_req=0
    sum_cluster_mem_req=0
    sum_cluster_cpu_limit=0
    sum_cluster_mem_limit=0
    sum_cluster_disk=0
    sum_cluster_pod=0

    echo "Namespace CPU_Req CPU_Limit MEM_Req(Gi) MEM_Limit(Gi) Disk(Gi) PODs"

    num=0
    for ns in ${ns_list}
    do
        num=$((${num}+1))
        pods_info=$(kubectl ${kubeconfig_options} get pod -n ${ns} -o json | jq '[.items[] | {ns:.metadata.namespace,resources:.spec.containers[].resources}]')

        sum_cpu_req=0
        sum_cpu_limit=0
        sum_mem_req=0
        sum_mem_limit=0
        sum_disk=0
        sum_pod=0

        for cpu_req in $(echo ${pods_info} | jq -r --arg ns "$ns" '.[] | select(.ns==$ns) | .resources.requests.cpu' | grep -v null)
        do
            if [[ ${cpu_req} == *m ]]
            then
                sum_cpu_req=$(echo "${sum_cpu_req} + ${cpu_req/m/}" | bc)
            else
                sum_cpu_req=$(echo "${sum_cpu_req} + ${cpu_req} * 1000" | bc)
            fi
        done
        sum_cpu_req=$(echo "scale=2; ${sum_cpu_req}/1000" | bc)

        for cpu_limit in $(echo ${pods_info} | jq -r --arg ns "$ns" '.[] | select(.ns==$ns) | .resources.limits.cpu' | grep -v null)
        do
            if [[ ${cpu_limit} == *m ]]
            then
                sum_cpu_limit=$(echo "${sum_cpu_limit} + ${cpu_limit/m/}" | bc)
            else
                sum_cpu_limit=$(echo "${sum_cpu_limit} + ${cpu_limit} * 1000" | bc)
            fi
        done
        sum_cpu_limit=$(echo "scale=2; ${sum_cpu_limit}/1000" | bc)

        for mem_req in $(echo ${pods_info} | jq -r --arg ns "$ns" '.[] | select(.ns==$ns) | .resources.requests.memory' | grep -v null)
        do
            case ${mem_req} in
                *G)
                    sum_mem_req=$(echo "${sum_mem_req} + ${mem_req/G/} * 1000 * 1000 * 1000" | bc)
                    ;;
                *Gi)
                    sum_mem_req=$(echo "${sum_mem_req} + ${mem_req/Gi/} * 1024 * 1024 * 1024" | bc)
                    ;;
                *M)
                    sum_mem_req=$(echo "${sum_mem_req} + ${mem_req/M/} * 1000 * 1000" | bc)
                    ;;
                *Mi)
                    sum_mem_req=$(echo "${sum_mem_req} + ${mem_req/Mi/} * 1024 * 1024" | bc)
                    ;;
                *K)
                    sum_mem_req=$(echo "${sum_mem_req} + ${mem_req/K/} * 1000" | bc)
                    ;;
                *Ki)
                    sum_mem_req=$(echo "${sum_mem_req} + ${mem_req/Ki/} * 1024" | bc)
                    ;;
                *)
                    sum_mem_req=$(echo "${sum_mem_req} + ${mem_req}" | bc)
                    ;;
            esac
        done

        for mem_limit in $(echo ${pods_info} | jq -r --arg ns "$ns" '.[] | select(.ns==$ns) | .resources.limits.memory' | grep -v null)
        do
            case ${mem_limit} in
                *G)
                    sum_mem_limit=$(echo "${sum_mem_limit} + ${mem_limit/G/} * 1000 * 1000 * 1000" | bc)
                    ;;
                *Gi)
                    sum_mem_limit=$(echo "${sum_mem_limit} + ${mem_limit/Gi/} * 1024 * 1024 * 1024" | bc)
                    ;;
                *M)
                    sum_mem_limit=$(echo "${sum_mem_limit} + ${mem_limit/M/} * 1000 * 1000" | bc)
                    ;;
                *Mi)
                    sum_mem_limit=$(echo "${sum_mem_limit} + ${mem_limit/Mi/} * 1024 * 1024" | bc)
                    ;;
                *K)
                    sum_mem_limit=$(echo "${sum_mem_limit} + ${mem_limit/K/} * 1000" | bc)
                    ;;
                *Ki)
                    sum_mem_limit=$(echo "${sum_mem_limit} + ${mem_limit/Ki/} * 1024" | bc)
                    ;;
                *)
                    sum_mem_limit=$(echo "${sum_mem_limit} + ${mem_limit}" | bc)
                    ;;
            esac
        done

        for disk_req in $(kubectl ${kubeconfig_options} -n $ns get pvc -o json | jq -r .items[].status.capacity.storage | grep -v null)
        do
            case ${disk_req} in
                *G)
                    sum_disk=$(echo "${sum_disk} + ${disk_req/G/}*1000*1000*1000/1024/1024/1024" | bc)
                    ;;
                *Gi)
                    sum_disk=$(echo "${sum_disk} + ${disk_req/Gi/}" | bc)
                    ;;
                *M)
                    sum_disk=$(echo "${sum_disk} + ${disk_req/M/}*1000*1000/1024/1024/1024" | bc)
                    ;;
                *Mi)
                    sum_disk=$(echo "${sum_disk} + ${disk_req/Mi/}/1024" | bc)
                    ;;
            esac
        done

        sum_pod=$(kubectl ${kubeconfig_options} -n $ns get pod --no-headers | wc -l)

        sum_cluster_cpu_req=$(echo "${sum_cluster_cpu_req} + ${sum_cpu_req}" | bc)
        sum_cluster_mem_req=$(echo "${sum_cluster_mem_req} + ${sum_mem_req}" | bc)
        sum_cluster_cpu_limit=$(echo "${sum_cluster_cpu_limit} + ${sum_cpu_limit}" | bc)
        sum_cluster_mem_limit=$(echo "${sum_cluster_mem_limit} + ${sum_mem_limit}" | bc)
        sum_cluster_disk=$(echo "${sum_cluster_disk} + ${sum_disk}" | bc)
        sum_cluster_pod=$(echo "${sum_cluster_pod} + ${sum_pod}" | bc)

        echo ${ns} ${sum_cpu_req} ${sum_cpu_limit} $(echo "${sum_mem_req} / 1024 / 1024 / 1024" | bc) $(echo "${sum_mem_limit} / 1024 / 1024 / 1024" | bc) ${sum_disk} ${sum_pod}
    done

    if [[ ${num} -gt 1 ]]; then
        echo SUM: ${sum_cluster_cpu_req} ${sum_cluster_cpu_limit} $(echo "${sum_cluster_mem_req} / 1024 / 1024 / 1024" | bc) $(echo "${sum_cluster_mem_limit} / 1024 / 1024 / 1024" | bc) ${sum_cluster_disk} ${sum_cluster_pod}
    fi
}

print_nodes_resources()
{
    kubeconfig_options=$1

    nodes=$(kubectl ${kubeconfig_options} get node | grep -v NAME | awk '{print $1}')

    echo "Node Pod CPU_Req CPU_Req(%) CPU_Limit CPU_Limit(%) MEM_Req MEM_Req(%) MEM_Limit MEM_Limit(%)"
    for node in ${nodes}
    do
        tmp_file=$(mktemp)
        kubectl ${kubeconfig_options} describe node ${node} > ${tmp_file}
        pod_num=$(cat ${tmp_file} | grep Non-terminated | cut -d'(' -f2 | cut -d' ' -f1)
        cpu_req=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep cpu | tr -s ' ' | cut -d ' ' -f3)
        if [[ ${cpu_req} == *m ]]
        then
            cpu_req=$(echo "scale=1; ${cpu_req/m/}/1000" | bc)
        fi
        cpu_req_p=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep cpu | tr -s ' ' | cut -d ' ' -f4 | sed 's/[()]//g')
        cpu_limit=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep cpu | tr -s ' ' | cut -d ' ' -f5)
        cpu_limit_p=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep cpu | tr -s ' ' | cut -d ' ' -f6 | sed 's/[()]//g')
        if [[ ${cpu_limit} == *m ]]
        then
            cpu_limit=$(echo "scale=1; ${cpu_limit/m/}/1000" | bc)
        fi
        mem_req=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep memory | tr -s ' ' | cut -d ' ' -f3)
        if grep '^[[:digit:]]*$' <<< "${mem_req}" > /dev/null
        then
            mem_req="$(echo "scale=0; ${mem_req}/1024/1024/1024" | bc)Gi"
        fi
        mem_req_p=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep memory | tr -s ' ' | cut -d ' ' -f4 | sed 's/[()]//g')
        mem_limit=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep memory | tr -s ' ' | cut -d ' ' -f5)
        if grep '^[[:digit:]]*$' <<< "${mem_limit}" > /dev/null
        then
            mem_limit="$(echo "scale=0; ${mem_limit}/1024/1024/1024" | bc)Gi"
        fi
        mem_limit_p=$(cat ${tmp_file} | grep -A10 "Allocated resources:" | grep memory | tr -s ' ' | cut -d ' ' -f6 | sed 's/[()]//g')
        echo ${node} ${pod_num} ${cpu_req} ${cpu_req_p} ${cpu_limit} ${cpu_limit_p} ${mem_req} ${mem_req_p} ${mem_limit} ${mem_limit_p}
        rm ${tmp_file}
    done
}



while getopts 'c:k:n:h' OPT; do
    case $OPT in
        c) cluster="$OPTARG";;
        k) cluster="$OPTARG";;
        n) namespaces="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done

default_kc_dir="/lab/pccc_utils/scripts/kubeconfig"

if [[ -z ${cluster} ]]; then
    kubeconfig_options=''
else
    kubeconfig_options="--kubeconfig=${default_kc_dir}/${cluster}.config"
fi

kubectl ${kubeconfig_options} get nodes 1>/dev/null
if [[ $? -ne 0 ]]; then
    echo "Failed to connect to the cluster. Exit!"
    exit 1
fi

if [[ -z ${namespaces} ]]; then
    ns_list=$(kubectl ${kubeconfig_options} get ns -o json | jq -r .items[].metadata.name)
else
    ns_list=${namespaces}
fi

echo
print_resource_allocation "${kubeconfig_options}" "${ns_list}" | column -t

echo

if [[ -z ${namespaces} ]]; then
    print_nodes_resources "${kubeconfig_options}" | column -t
fi
