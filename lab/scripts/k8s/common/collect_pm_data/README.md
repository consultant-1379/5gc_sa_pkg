# collect_prom.py
## This script will collect data from prometheus and victoria metrics
## How to use collect_prom.py:


### If needed, Configure the pm-servers http port
Some products have disabled http port by default.

If needed, add http port 9090 to pm-server.
~~~
kubectl -n $ns patch svc eric-pm-server -p '{"spec": {"ports": [{"name": "http", "port": 9090, "protocol": "TCP", "targetPort": 9090}]}}'
~~~

### If needed, Configure the pm-servers networkPolicies
Some products have networkspolicies that limit communication outside the namespace
~~~
kubectl -n $ns get networkpolicy
~~~
If needed, Create a networkpolicy to allow traffic to eric-pm-server service. Example:
https://gerrit.ericsson.se/plugins/gitiles/pc/vepc/cloud-configs/+/master/n63_baremetal/eccd1/ccdm/1.8/allow-eric-pm-server-NetworkPolicy.yaml
~~~
kubectl -n $ns apply -f allow-eric-pm-server-NetworkPolicy.yaml
~~~

### Create ingess for pm-server
Check if ingress is already present:
kubectl -n $ns get ingress

Example of how to create pm-server ingress:
~~~~
export ns=pcc
export svc=eric-pm-server
export port=9090
export host=eric-pm-server-pcc.node89.sero.gic.ericsson.se
kubectl -n $ns create ingress $svc --rule="$host/*=$svc:$port"
~~~~



## update  critical_pods.csv 

Exmaple:
~~~
ccdm,eric-ingressgw-udr-traffic
ccdm,eric-udr-kvdb-ag-locator
ccdm,eric-udr-kvdb-ag-server
~~~

## Update  collect_prom_config.yaml:

Update  collect_prom_config.yaml according to you enviroment

Uptate the test time
~~~
start: "2022-12-18T12:00:00"
end: "2022-12-18T16:00:00"

~~~

metrics section will collect all metrics as json. 
if pmtype is set to victoria-metrics the data will be collected in victoria metrics native format with 1 min step and json with a 1h step, to save space.

Example:
~~~
servers:
  monitoring:
    host: "victoria-metrics.node63.sero.gic.ericsson.se"
    pmtype: victoria-metrics
    api: "/select/0/prometheus/api/v1/"
    metrics:
    - kube_pod_container_status_ready
    - container_cpu_usage_seconds_total
~~~

For victoria metrics the API is 
~~~
/select/0/prometheus/api/v1/
~~~

and for prometheus
~~~
/api/v1/
~~~


For CCD cluster monitoing victoria metrics server the script can generate a statistics table for critical pods:

Example:
~~~
    criticalPodsTable:
      - unit: integer
        target: 'sum(avg%20by%20(pod)(avg_over_time(kube_pod_container_info\{\})))'
        name: Replicas

      - unit: percent
        target: avg(avg_over_time(container_memory_usage_bytes\{container=\"\",image=\"\"\}))/sum(avg%20by%20(container)(avg_over_time(kube_pod_container_resource_requests\{resource=\"memory\"\})))
        name: Memory/Request
~~~
* Unit will determine the output formating. Possible values are integer/percent/gibiByte/float
* target should be a prometheus query. Special characters { and " need to be escaped, Spaces need to be replaced by %20. Namespaces and pod filter will be added by the script.
* The Query should only output 1 value, so the query need to be maxed/summed/averaged over time/container/pod.
https://prometheus.io/docs/prometheus/latest/querying/functions/
* Name is the column title.


For PCG data-plane pod CPU table can be generated with:

~~~
  pcg:
    dpPodtable: ["Egress", "Ingress"]
~~~

#  Run script

~~~
 ./collect_prom.sh --conf collect_prom_config.yaml --critpods  critical_pods.csv
~~~

If there are any error, try to run the curl command manualy to see the output error.


