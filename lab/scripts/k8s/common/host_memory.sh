#!/usr/bin/env bash


help()
{
    echo "This script collect memory usage log in the cluster."
    echo " -c <cluster> -t <start collect log time> -p <log collect period hours> "
    echo "Example: host_memory.sh -c n99 -t \"2021-10-27 04:51:00\" -p 0.25 "
    exit 1
}


while getopts 'e:c:n:t:p:h' OPT; do
    case $OPT in
        e) evnfm="$OPTARG";;
        c) cluster="$OPTARG";;
        n) namespace="$OPTARG";;
        t) end_time="$OPTARG";;
        p) period="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done

#if [[ $namespace ]];then
#       ns=$namespace
#else
#       ns="pcc pcg ccrc ccdm ccsm kube-system"
#fi


if [[ $end_time ]];then
        endtime=`date -d"$end_time" +%s`
else
        endtime=`date  +%s`
fi

#number_period=`echo $period | tr -d "[:alpha:][:blank:] "`
int_period_sec=`echo "scale=0;$period * 3600/1"|bc`
start_time=$[$endtime - $int_period_sec]
starttime=`date -d @$(($start_time)) +%s`
logname="host_memory"`date -d @$endtime +"%Y-%m-%d_%H-%M-%S" `.json

curl_savefile () {
  curl http://monitoring-eric-victoria-metrics-cluster-vmselect.ingress.$evnfm-$cluster.sero.gic.ericsson.se/select/0/prometheus/api/v1/export -d 'match[]=node_memory_MemTotal_bytes' -d 'start='$starttime'' -d 'end='$endtime''|jq . >> $logname
}

if [[ $(echo "$period > 24.00"|bc) -eq 1 ]];then
   count=$[$period / 24]
   tmp=$endtime
   echo $tmp
   for i in `eval echo {1..$count}`;
   do
        endtime=$[$starttime + 86400]
        curl_savefile
        starttime=$endtime
   done
   endtime=$tmp
   curl_savefile
fi

if [[ $(echo "$period <= 24.00"|bc) -eq 1 ]];then
   curl_savefile
fi



