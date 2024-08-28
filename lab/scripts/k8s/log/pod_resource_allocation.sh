#!/bin/bash
convert_unit()
        {
resource_limit=$1
case ${resource_limit} in
            *G)
                sum_resource_limit=$(expr  ${resource_limit/G/} \* 1000 \* 1000 \* 1000)
                ;;
            *Gi)
                sum_resource_limit=$(expr ${resource_limit/Gi/} \* 1024 \* 1024 \* 1024)
                ;;
            *M)
                sum_resource_limit=$(expr  ${resource_limit/M/} \* 1000 \* 1000)
                ;;
            *Mi)
                sum_resource_limit=$(expr  ${resource_limit/Mi/} \* 1024 \* 1024)
                ;;
            *K)
                sum_resource_limit=$(expr   ${resource_limit/K/} \* 1000)
                ;;
            *Ki)
                sum_resource_limit=$(expr   ${resource_limit/Ki/} \* 1024)
                ;;
            *m)
                sum_resource_limit=$(expr   ${resource_limit/m/} \* 1)
                ;;
            *)
                sum_resource_limit=$(expr   ${resource_limit} \* 1000)
                ;;
        esac
echo $sum_resource_limit
}

convert_unit_mem()
        {
resource_limit=$1
case ${resource_limit} in
            *G)
                sum_resource_limit=$(expr  ${resource_limit/G/} \* 1000 \* 1000 \* 1000)
                ;;
            *Gi)
                sum_resource_limit=$(expr ${resource_limit/Gi/} \* 1024 \* 1024 \* 1024)
                ;;
            *M)
                sum_resource_limit=$(expr  ${resource_limit/M/} \* 1000 \* 1000)
                ;;
            *Mi)
                sum_resource_limit=$(expr  ${resource_limit/Mi/} \* 1024 \* 1024)
                ;;
            *K)
                sum_resource_limit=$(expr   ${resource_limit/K/} \* 1000)
                ;;
            *Ki)
                sum_resource_limit=$(expr   ${resource_limit/Ki/} \* 1024)
                ;;
            *m)
                sum_resource_limit=$(expr   ${resource_limit/m/} \* 1)
                ;;
            *)
                sum_resource_limit=$(expr   ${resource_limit} \* 1)
                ;;
        esac
echo $sum_resource_limit
}

if [ $# -gt 0 ]
then
key=$*
else
key="pcc1 pcc2 pcg ccrc ccsm ccdm sc eda cces"
fi

for namespace in `echo $key`
do
kubectl get ns $namespace  > /dev/null 2>&1
if [ $? -eq 1 ]
then
echo "namespace $namespace not exist, skip to collect $namespace and  continue"
continue
fi
cnf_tmp=$(mktemp)
pod=$(mktemp)
pod_res=$(mktemp)
pod_dimension=$(mktemp)

kubectl describe nodes  |grep   "^  "$namespace"" > $cnf_tmp
cat  $cnf_tmp | sort  |awk '{print $2}' |awk -F '-' -v OFS='-' '{NF-=1}1'  > $pod
cat $cnf_tmp | sort  |awk '{print $3,$5,$7,$9}' > $pod_res
cat -n $pod > $pod"_1"
cat -n $pod_res> $pod_res"_1"
join $pod"_1" $pod_res"_1" |awk '{print $2,$3,$4,$5,$6}' > $pod_dimension

while read line
do
pod_name=`echo "$line"|awk '{print $1}'`;echo -n  "$namespace"" "$pod_name" "
cpu_req=$(convert_unit $(echo $line|awk '{print $2}'));echo -n $cpu_req" "
cpu_limit=$(convert_unit $(echo $line|awk '{print $3}'));echo -n $cpu_limit" "
mem_req=$(convert_unit_mem $(echo $line|awk '{print $4}'));echo -n $mem_req" "
mem_limit=$(convert_unit_mem $(echo $line|awk '{print $5}'));echo $mem_limit
done < $pod_dimension  > /tmp/"$namespace"


cat $pod  | sort |uniq -c   |awk '{print $2 ,$1}'  | sort -r >   /tmp/"$namespace"_stat_dep


while read line
do
pod=`echo $line|awk '{print $1}'`
replica=`echo $line|awk '{print $2}'`
echo `grep $pod /tmp/$namespace|sed -n '1p'` $replica   &&  sed -i "/$pod/d" /tmp/"$namespace"
done < /tmp/"$namespace"_stat_dep

rm -rf $cnf_tmp $pod $pod_res $pod_dimension $pod"_1" $pod_res"_1"
rm -rf  /tmp/$namespace  /tmp/"$namespace"_stat_dep
done
