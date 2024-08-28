help()
{
    echo "This script collect isp log in the cluster."
    echo "run example: isp_log_collect.sh -e <environment> -c <cluster> -d <log end time> -n <log during days> "
    echo "example:isp_log_collect.sh -e n28 -c eccd1 -d 2021-08-16 -n 3 "
    exit 1
}


while getopts 'e:c:d:n:h' OPT; do
    case $OPT in
        e) EVNFM="$OPTARG";;
        c) cluster="$OPTARG";;
        d) endtime="$OPTARG";;
        n) lasttime="$OPTARG";;
        h) help;;
        ?) help;;
    esac
done


namespace=pcc
rawlogname=rawisp`date +%Y-%m-%d-%H-%M-%S`
logname=isp`date +%Y-%m-%d-%H-%M-%S`
yymm=`date -d $endtime +%Y-%m-%d`
day=`date +%s -d "$yymm"`

for((i=0;i < $lasttime;i++))
do
duringtime=`expr 86400 \* $i`
datetime=`expr $day - $duringtime`
daytime=`date -d @$(($datetime)) +%Y.%m.%d`
#ip=`kubectl get svc -n pcc -l app.kubernetes.io/name=eric-data-search-engine |grep -vE "tls|ingest|tran|dis|NAME"|awk '{print $3}'`
curl -s http://pcc-eric-data-search-engine.ingress."$EVNFM"-"$cluster".sero.gic.ericsson.se/_msearch  \
-H 'cache-control: no-cache' \
-H 'content-type: application/x-ndjson' \
-d '{"index":["pcc-isp-log-'$daytime'"],"search_type":"query_then_fetch"}
{"size":10000},{"query":{"bool": {"filter":[{"range": {"timestamp": {"format":"epoch_millis"}}}},"match_all":{}}}
'| jq . >> $rawlogname.json
done

while read line

do

echo $line|grep -E '@timestamp|pod_name|message|status'|tee -a  $logname.txt

done < $rawlogname.json

