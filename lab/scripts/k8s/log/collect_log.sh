#!/bin/bash

if [[ "$#" -lt "1" ]]; then
    echo "Wrong number of arguments"
    echo "Usage collect_k8s_logs.sh <Kubernetes_namespace>"
    echo "ex:"
    echo "$0 default    #--- to gather the logs for namespace 'default'"
    exit 1
fi

namespaces=$*

get_describe_info() {
    #echo "---------------------------------------"
    echo "-Getting logs for describe info-"
    #echo "---------------------------------------"
    #echo "---------------------------------------"

    des_dir=${log_base_path}/describe
    mkdir ${des_dir}
    for attr in statefulsets deployments services replicasets endpoints daemonsets persistentvolume persistentvolumeclaims configmap pods nodes jobs persistentvolumes rolebindings roles secrets serviceaccounts storageclasses ingresses
        do
            dir=`echo $attr | tr '[:lower:]' '[:upper:]'`
            mkdir ${des_dir}/$dir
            kubectl --namespace ${namespace} get $attr > ${des_dir}/$dir/$attr.txt
            echo "Getting describe information on $dir.."
            for i in `kubectl --namespace ${namespace} get $attr | grep -v NAME | awk '{print $1}'`
                do
                    kubectl --namespace ${namespace}  describe  $attr  $i > ${des_dir}/$dir/$i.txt
                done
        done
}
get_events() {
    echo "-Getting list of events -"
    des_dir=${log_base_path}/events
    mkdir ${des_dir}

    kubectl --namespace ${namespace} get events > ${des_dir}/events.txt
}


get_pods_logs() {
    #echo "---------------------------------------"
    echo "-Getting logs per POD-"
    #echo "---------------------------------------"
    #echo "---------------------------------------"

    logs_dir=${log_base_path}/logs
    mkdir ${logs_dir}
    kubectl --namespace ${namespace} get pods > ${logs_dir}/kube_podstolog.txt
    for i in `kubectl --namespace ${namespace} get pods | grep -v NAME | awk '{print $1}'`
        do
            for j in `kubectl --namespace ${namespace} get pod $i -o jsonpath='{.spec.containers[*].name}'`
                do
                    kubectl --namespace ${namespace} logs $i -c $j > ${logs_dir}/${i}_${j}.txt
                done
        done
}

get_helm_info() {
    #echo "-----------------------------------------"
    echo "-Getting Helm Charts for the deployments-"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"

    helm_dir=${log_base_path}/helm
    mkdir ${helm_dir}
    helm --namespace ${namespace} list > ${helm_dir}/helm_deployments.txt

    for i in `helm --namespace ${namespace} list| grep -v NAME | awk '{print $1}'`
        do
            #echo $i
            helm get $i > ${helm_dir}/$i.txt
        done
}

get_common_info() {
    #echo "-----------------------------------------"
    echo "-Get node pod common info-"
    #echo "-----------------------------------------"
    #echo "-----------------------------------------"
    common_dir=${log_base_path}/common
    mkdir ${common_dir}
    kubectl top node > ${common_dir}/topnode.log;
    kubectl get node -o wide > ${common_dir}/node.log
    kubectl describe node > ${common_dir}/describenode.log
    kubectl top pod -n ${namespace} > ${common_dir}/toppod.log
    kubectl describe pod -n ${namespace} > ${common_dir}/describepod.log
}



for namespace in $namespaces;do
  log_base_dir=logs_${namespace}_$(date "+%Y-%m-%d-%H-%M-%S");
  log_base_path=$PWD/${log_base_dir};
  mkdir ${log_base_dir};
  #get_describe_info;
  get_helm_info;
  get_events;
  get_pods_logs;
  get_common_info;
done
