#!/usr/bin/env bash
# ----------------------------------------------------------------------------
# Auther: ken.shi@ericsson.com
# ----------------------------------------------------------------------------
help()
{
    echo "Usage: $0 -c cluster [ -n namespace ] -f json_file"
    exit 1
}

update_dashboard_configmap()
{
    kubeconfig_file=$1
    json_file=$2
    echo -n "-> Updating Grafana dashboard '${json_file}'..."
    echo ${json_file} | grep -q '\.json'
    if [[ $? -ne 0 ]]; then
        echo "Error: invalid json file name: ${json_file}"
        return 1
    fi
    kubeconfig_options="--kubeconfig=${kubeconfig_file}"
    cm_name="grafana-dashboard-$(basename ${json_file} | sed 's/.json$//g' |sed 's/[A-Z]/\l&/g')"

    kubectl ${kubeconfig_options} -n ${ns} get cm ${cm_name} > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        kubectl ${kubeconfig_options} -n ${ns} create cm ${cm_name} --from-file ${json_file} -o yaml --dry-run=client | kubectl ${kubeconfig_options} replace -f -
    else
        kubectl ${kubeconfig_options} -n ${ns} create cm ${cm_name} --from-file ${json_file}
    fi
}

while getopts 'c:f:n:ah' OPT; do
    case $OPT in
        c) cluster="$OPTARG";;
        f) json_file="$OPTARG";;
        n) ns="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done
default_kc_dir="/lab/pccc_utils/scripts/kubeconfig"

if [[ -z ${cluster} ]]; then
    echo "Error: missing '-c' argument"
    help
fi
if [[ -z ${json_file} ]]; then
    echo "Error: missing '-f' argument"
    help
fi

if [[ -d ${json_file} ]]; then
    json_file="${json_file}/*json"
fi

file_list=$(ls -1 ${json_file})

if [[ -z ${ns} ]]; then
    ns='grafana'
fi

for cluster_name in ${cluster[@]}
do
    echo "==> Updating grafana dashboard on cluster ${cluster_name}"
    kubeconfig_file="${default_kc_dir}/${cluster_name}.config"
    if [[ ! -f ${kubeconfig_file} ]]; then
        echo "Error: kubeconfig file ${kubeconfig_file} doesn't exist"
        continue
    fi
    for file in ${file_list[@]}
    do
        update_dashboard_configmap ${kubeconfig_file} ${file}
    done
done
