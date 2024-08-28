#!/usr/bin/env python3



import sys
import os
import subprocess
import yaml
import re
import json
import argparse
from datetime import datetime

def collectJson(servername,host,metric,api,step):
    global start_timestamp
    global end_timestamp

    command=[ "curl","-ks", f"https://{host}{api}query_range?query={metric}&start={start_timestamp}&end={end_timestamp}&step={step}" ]
    out=subprocess.run(command, stdout=subprocess.PIPE)

    if out.stderr != None :
        print(f"Error connecting to {servername}")
        print(out.stderr )
        print(" ".join(command))
        return
    try:
        result =out.stdout.decode("utf-8")
        jsoncontent = json.loads(result)
    except:
        print(f"Error response for {servername} {metric} not json")
        print(result)
    if len(jsoncontent.get('data',{}).get('result',[]))<1:
        print(f"Error no metrics in response for {servername} {metric}")
        print(result)
        print("".join(command))
        return
    elif len(jsoncontent['data']['result'][0].get('values',[]))<1:
        print(f"Error no values in response for {servername} {metric}")
        print(result)
        print("".join(command))
        return

    with open(f"pm_metrics/{servername}_{metric}.json","w") as file:
        file.write(result)
    print(f"Successlully collected {servername} {metric} json")

def collectVictoriaNative(servername,host,metric,api):
    global start_timestamp
    global end_timestamp
    command=f"curl -ks https://{host}{api}export/native  -d \'match[]={metric}\' -d \"start={start_timestamp}\" -d \"end={end_timestamp}\"  > pm_metrics/{servername}_{metric}.bin"    
    process_command = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    out, err = process_command.communicate()
    if (err != b'') or (out == None):
        print(f"Error no values in response for {servername} {metric}")
        print(err)
        print(command)
        return
    print(f"Successlully collected {servername} {metric} victoria metrics native format")


def collectSingleValue(host,query,api):
    global end_timestamp
    command=f'curl -k \"https://{host}{api}query?query={query}&time={end_timestamp}" |jq -r \'.data.result[0].value[1]\' '
    process_command = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
    process_command.wait()
    out, err = process_command.communicate()
    if out == None or len(out)==0:
        print(f"Error no values in response for {host} {query}")
        print(err)
        print(out)
        print(command)
    return out.decode('ascii')


def replicasQuery(namespace,podname,target):
    global timerange
    podstring=f'namespace=\\"{namespace}\\",pod=~\\"{podname}.*\\",'
    timestring=f'\[{timerange}s\]'

    #Add pod and namespace selector
    targetwithpod=re.sub(r'({)', r'\1'+podstring, target)

    # Remove trailing comma
    targetwithpod=re.sub(r',\}', r'\}', targetwithpod)

    #Add timerange to all metrics
    targetwithpodandtime=re.sub(r'(})', r'\1'+timestring, targetwithpod) 
    return targetwithpodandtime

def critPodTable(servername,critPodsList,server):
    columnlist=server["criticalPodsTable"]
    host=server["host"]
    api=server["api"]
    critPodTable="ns, pod"

    for column in columnlist:


        str1=column["name"]
        critPodTable+=f", {str1}"
            
    critPodTable+="\n"

    for pod in critPodsList:
        podname=pod[1]
        namespace=pod[0]
        
        critPodTable+=f"{namespace}, {podname}"
        for column in columnlist:
            columnName=column["name"]
            try:
                query=replicasQuery(namespace,podname,column["target"]) 

                out=collectSingleValue(host,query,api)

                if column["unit"]=="float":
                    critPodTable+=f", {float(out):.2f}"
                elif column["unit"]=="integer":
                    critPodTable+=f", {int(out)}"
                elif column["unit"]=="percent":
                    critPodTable+=f", {float(out)*100:.2f} %"
                elif column["unit"]=="gibiByte":
                    critPodTable+=f", {(float(out)/2**30):.2f} GiB"
                print(f"successfully collected {namespace} {podname} {columnName} from {servername}")
            except Exception as e: 
                print(e)
                print(f"error collecting {namespace}, {podname} {column}")

        critPodTable+="\n"

    with open(f"critPodTable_{servername}.csv","w") as file:
        file.write(critPodTable)

        
def pcgDpPodTable(servername,roles,host,api):
    pcgDpPod=""
    #  pcg DP pod CPU

    pcgDpPod+="Egress CPU, Ingress  CPU \n"
    for role in roles: 
        try:
            query= f'avg(avg_over_time(pc_up_cpu_load_5s_average_percent\{{role=\\"{role}\\"\\}}\[{timerange}s\]))'
            out=collectSingleValue(host,query,api)
            pcgDpPod+=f", {float(out):.2f} %"
        except Exception as e: 
            print(e)
            print(f"error collecting PCG UPF Data-plane {role} CPU")
    pcgDpPod+=f"\n"

    with open(f"pcgDpPod_{host}.csv","w") as file:
        file.write(pcgDpPod)

parser = argparse.ArgumentParser()
parser.add_argument('--conf', type=str, required=True)
parser.add_argument('--critpods', type=str, required=True)
args = parser.parse_args() 

file=args.conf
if not os.path.isfile(file):
    print('File ' + file + ' does not exist. Exiting...')
    sys.exit()
with open(file, 'r') as f:
    configDict=yaml.safe_load(f)

start_timestr=configDict["start"]
end_timestr=configDict["end"]

start_timestamp = str(int(datetime.timestamp(datetime.strptime(start_timestr, "%Y-%m-%dT%H:%M:%S"))))
end_timestamp = str(int(datetime.timestamp(datetime.strptime(end_timestr, "%Y-%m-%dT%H:%M:%S") )))
timerange=str(int(end_timestamp)-int(start_timestamp)) 


pm_metrics_folder= "pm_metrics"
if not os.path.isdir(pm_metrics_folder):
    os.mkdir(pm_metrics_folder)


try:
    FILE = open(args.critpods)
except:
    print('Can not open file : {}'.format(critical_pods_filepath))
    sys.exit()

critPodsList = []
for row in FILE:
    data = row.lower().rstrip().split(",")
    critPodsList.append(data)



for servername in configDict["servers"]:
    server=configDict["servers"][servername]
    if server["pmtype"]=="victoria-metrics":
        for metric in server.get("metrics",[]):
            collectVictoriaNative(servername,server["host"],metric,server["api"])
            collectJson(servername,server["host"],metric,server["api"],"1h")
    elif server["pmtype"]=="prometheus":
        for metric in server.get("metrics",[]):
            collectJson(servername,server["host"],metric,server["api"],"5m")
    else: 
        print(f"pmtype  not recognised")
    if "criticalPodsTable" in server:
        critPodTable(servername,critPodsList,server)
    if "dpPodtable" in server:
        pcgDpPodTable(servername,server["dpPodtable"],server["host"],server["api"])


