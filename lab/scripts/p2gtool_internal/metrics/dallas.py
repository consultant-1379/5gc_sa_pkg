#!/usr/bin/env python

import os
import shlex
import logging
import subprocess
import socket


def gen_dls_metrics(host, dls_type="", instance="", prefix=""):
    """get metrics from stats_script outputs"""
    log = logging.getLogger(__name__)
    metrics = []
    labels_dict = {'dls_type': dls_type,
                   'instance': instance}
    basedir = os.path.dirname(__file__)
    stats_script_path = os.path.join(
        basedir,
        "metric_gen/dallas",
        "{0}.sh".format(dls_type))
    if host not in socket.gethostname():
        log.error("Stopped! Make sure execute it on host {1}.".format(
           stats_script_path, host))
        return metrics
    if not os.path.exists(stats_script_path):
        log.error("Stopped!, the script {0} not found.".format(
            stats_script_path))
        return metrics
    rc, outputs = _execute_shell_cmd(stats_script_path)
    if rc != 0:
        return metrics
    try:
        metrics.extend(
            [{'name': _add_prefix(i.split('=')[0], prefix),
              'values': [[list(labels_dict.values()), float(i.split('=')[1])]],
              'type': 'Gauge',
              'labels': list(labels_dict.keys()),
              'desc': i.split('=')[0]}
             for i in shlex.split(outputs.decode())])
    except:
        pass
    return metrics


def _execute_shell_cmd(cmd):
    """return code and outputs on running cmd on host"""
    child = subprocess.Popen(cmd, shell=True,
                             stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT)
    rc = child.wait()
    stdout = child.stdout.read()
    return rc, stdout


def _add_prefix(name, prefix=""):
    """add prefix to name if prefix defined"""
    return '_'.join([prefix, name]) if prefix else name
