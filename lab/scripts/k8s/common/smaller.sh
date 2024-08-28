#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Author: ken.shi@ericsson.com
# ----------------------------------------------------------------------------
help()
{
    echo "Usage: $0 -k cluster -n namespace"
    echo "Example: ./smaller.sh -k pod56-eccd1 -n ccrc"
    exit 1
}

set_requests()
{
    kubeconfig_options=$1
    ns=$2
    kind=$3
    pod=$4
    echo -n "--> Patch ${kind} ${pod} ... "
    N_containers=$(kubectl ${kubeconfig_options} -n ${ns} get ${kind} ${pod} -o jsonpath='{.spec.template.spec.containers[*].name}' | wc -w)
    if [[ "${kind}" == "daemonsets" ]]; then
        available=$(kubectl ${kubeconfig_options} -n ${ns} get ${kind} ${pod} -o jsonpath='{.status.numberReady}')
    else
        available=$(kubectl ${kubeconfig_options} -n ${ns} get ${kind} ${pod} -o jsonpath='{.status.availableReplicas}')
    fi
    patch_json='{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "0"},{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "0"}'
    for i in $(seq 1 $(expr ${N_containers} - 1)); do
        patch_json=${patch_json}',{"op": "replace", "path": "/spec/template/spec/containers/'${i}'/resources/requests/cpu", "value": "0"},{"op": "replace", "path": "/spec/template/spec/containers/'${i}'/resources/requests/memory", "value": "0"}'
    done
    # echo ${patch_json}
    result=$(kubectl ${kubeconfig_options} -n ${ns} patch ${kind} ${pod} --type='json' -p="[${patch_json}]")
    if [[ "${result}" =~ "no change" ]]; then
        echo "No change"
        continue
    fi
    if [[ "${kind}" == "statefulsets" ]]; then
        sleep 10
    else
        sleep 1
    fi
    echo -n "      Waiting for all replicas recovered ... "
    while true; do
        if [[ "${kind}" == "daemonsets" ]]; then
            current_available=$(kubectl ${kubeconfig_options} -n ${ns} get ${kind} ${pod} -o jsonpath='{.status.numberReady}')
        else
            current_available=$(kubectl ${kubeconfig_options} -n ${ns} get ${kind} ${pod} -o jsonpath='{.status.availableReplicas}')
        fi
        if [[ ${current_available} -eq ${available} ]]; then
            break
        fi
        sleep 3
    done
    echo "OK"
}

disable_hpa()
{
    kubeconfig_options=$1
    ns=$2
    hpa_all=$(kubectl ${kubeconfig_options} -n ${ns} get hpa -o jsonpath='{.items[*].metadata.name}')
    echo "==>> Disable HPA"
    for hpa in ${hpa_all[@]}; do
        minReplicas=$(kubectl ${kubeconfig_options} -n ${ns} get hpa ${hpa} -o jsonpath='{.spec.minReplicas}')
        maxReplicas=$(kubectl ${kubeconfig_options} -n ${ns} get hpa ${hpa} -o jsonpath='{.spec.maxReplicas}')
        if [[ ${maxReplicas} -gt ${minReplicas} ]]; then
            echo -n "--> Disable HPA for ${hpa} ... "
            kubectl ${kubeconfig_options} -n ${ns} patch hpa ${hpa} --type='json' -p='[{"op": "replace", "path": "/spec/maxReplicas", "value": '${minReplicas}'}]'
        else
            echo "--> HPA for ${hpa} is already disabled"
        fi
    done
}

while getopts 'k:n:ah' OPT; do
    case $OPT in
        k) cluster="$OPTARG";;
        n) ns="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done
default_kc_dir="/lab/pccc_utils/scripts/kubeconfig"

if [[ -z ${cluster} ]]; then
    echo "Error: missing '-k' argument"
    help
fi

if [[ -z ${ns} ]]; then
    echo "Error: missing '-n' argument"
    help
fi

kubeconfig_file="${default_kc_dir}/${cluster}.config"
if [[ ! -f ${kubeconfig_file} ]]; then
    echo "Error: kubeconfig file ${kubeconfig_file} doesn't exist"
    exit 1
fi
kubeconfig_options="--kubeconfig=${kubeconfig_file}"

disable_hpa "${kubeconfig_options}" "${ns}"

kinds=(
    "deployments"
    "statefulsets"
    "daemonsets"
)

for kind in ${kinds[@]}; do
    pods=$(kubectl ${kubeconfig_options} -n ${ns} get ${kind} -o jsonpath='{.items[*].metadata.name}')
    echo
    echo "==>> Set CPU/Mem resources request to 0 for containers in all ${kind}"
    for pod in ${pods[@]}; do
        if [[ "${pod}" =~ "kvdb" || "${pod}" =~ "nudrfe" || "${pod}" =~ "topicwatcher"  || "${pod}" =~ "message-bus-kf" ]]; then
            echo "--> Skip patching ${pod}"
            continue
        fi
        if [[ "${pod}" =~ "pc-mm" || "${pod}" =~ "pc-sm" || "${pod}" =~ "pc-vpn" || "${pod}" =~ "pc-up" ]]; then
            echo "--> Skip patching ${pod}"
            continue
        fi
        set_requests "${kubeconfig_options}" "${ns}" "${kind}" "${pod}"
    done
done

