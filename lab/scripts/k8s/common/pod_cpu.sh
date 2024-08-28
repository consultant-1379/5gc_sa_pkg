#!/usr/bin/env bash


help()
{
    echo "This script collect cpu usage log in the vnf."
    echo " -e <cluster> -n <namespace> -t <collect log end time> -p <log collect period hours> "
    echo "Example: host_cpu.sh -e n99 -n pcc -t \"2021-10-27 04:51:00\" -p 0.25 "
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

if [[ $cluster="eccd1" ]] && [[ $cluster="eccd3" ]] && [[ $cluster="eccd5" ]];then
  if [[ $namespace = "all" ]];then
       ns="pcc pcg ccrc ccdm ccsm eda sc kube-system"
  else
       ns=$namespace
  fi
elif [[ $cluster = "eccd2" ]] && [[ $cluster = "eccd4" ]];then
  if [[ $namespace = "all" ]];then
       ns="evnfm kube-system"
  else
       ns=$namespace
  fi
fi


if [[ $end_time ]];then
        endtime=`date -d"$end_time" +%s`
else
        endtime=`date  +%s`
fi

#number_period=`echo $period | tr -d "[:alpha:][:blank:] "`
int_period_sec=`echo "scale=0;$period * 3600/1"|bc`
start_time=$[$endtime - $int_period_sec]
starttime=`date -d @$(($start_time)) +%s`

curl_savefile () {
  curl http://monitoring-eric-victoria-metrics-cluster-vmselect.ingress.$evnfm-$cluster.sero.gic.ericsson.se/select/0/prometheus/api/v1/export -d 'match=container_cpu_usage_seconds_total{name!="",namespace="'$i'",container=~".*"}' -d 'start='$starttime'' -d 'end='$endtime''|jq . >> $logname
}

filename="pod_cpu"`date -d @$endtime +"%Y-%m-%d_%H-%M-%S" `
mkdir $filename
cd $filename

if [[ $(echo "$period > 10.00"|bc) -eq 1 ]];then
   count=$[$period / 10]
   tmp_start=$starttime
   tmp_end=$endtime
   for i in $ns;
   do
       logname=$i"_pod_cpu".json
       for j in `eval echo {1..$count}`;
       do
           endtime=$[$starttime + 36000]
           curl_savefile
           starttime=$endtime
       done
       endtime=$tmp_end
       curl_savefile
       starttime=$tmp_start
   done
fi

if [[ $(echo "$period <= 10.00"|bc) -eq 1 ]];then
   for i in $ns;
   do
       logname=$i"pod_cpu".json
       curl_savefile
   done
fi


