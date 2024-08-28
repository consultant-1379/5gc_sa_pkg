#!/usr/bin/env python

import os
import shlex
import logging
import subprocess
import socket


def gen_redis_metrics(pod, cluster, namespace, instance=""):
    """get metrics from stats_script outputs"""
    log = logging.getLogger(__name__)
    metrics = []
    cluster = "-c {0}-{1}".format(pod,cluster)
    ns= "-n {0}".format(namespace)
    basedir = os.path.dirname(__file__)
    stats_script_path = os.path.join(
        basedir,
        "metric_gen/redis",
        "check_redis.sh")
    cmd = "{0} {1} {2}".format(stats_script_path, cluster, ns)
    if not os.path.exists(stats_script_path):
        log.error("Stopped!, the script {0} not found.".format(
            stats_script_path))
        return metrics
    outputs = subprocess.check_output(cmd,shell=True)
    try:
        role_list = [[] for i in range(5)]
        worker_list = []
        value_dict = {}
        labels_dict = {'instance': instance}
        name = 'check_redis'
        for line in outputs.decode().splitlines():
            if line.split("\t")[0] == 'pcc' or line.split("\t")[0] == 'pcg' :
                name_space = line.split("\t")[0]
                worker = line.split("\t")[1]
                redis_pod_name = line.split("\t")[2]
                role = line.split("\t")[3]
                peer_redis_pod = line.split("\t")[4]
                role_list[0].append(name_space)
                role_list[1].append(worker)
                role_list[2].append(redis_pod_name)
                role_list[3].append(role)
                role_list[4].append(peer_redis_pod)
        for i in set(role_list[0]):
            start = role_list[0].index(i)
            end = start + role_list[0].count(i) - 1
            worker_list = []
            for j in range(start, end):
                peer = role_list[4][j]
                if role_list[3][j] == "master":
                    for k in range(j + 1, end+1):
                        if role_list[2][k] == peer and role_list[3][k] == "slave":
                            if role_list[1][j] == role_list[1][k]:
                                worker_list.append(role_list[1][j])
                else:
                    for k in range(j + 1, end+1):
                        if role_list[2][k] == peer and role_list[3][k] == "master":
                            if role_list[1][j] == role_list[1][k]:
                                worker_list.append(role_list[1][j])

            name_space = role_list[0][end]
            labels_dict["namespace"] = name_space
            number = len(worker_list)
            value_dict.setdefault(name, [])
            value_dict[name].append([list(labels_dict.values()), number])

        for k, v in value_dict.items():
            metrics.append(dict(name=k,
                                values=v,
                                desc=k,
                                type="Gauge",
                                labels=list(labels_dict.keys())))


    except:
        pass
    return metrics

