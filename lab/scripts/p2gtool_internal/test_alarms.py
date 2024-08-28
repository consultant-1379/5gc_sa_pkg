#!/usr/bin/env python

import argparse
import os
import sys
import json
from misc import push_to_pg, setup_logging
from metrics import gen_actAlarms_metrics
import logging
from datetime import datetime, timedelta
import time
from hashlib import sha1


def save_to_file(content, logdir):
    """save alarms log to logfile"""
    if not os.path.exists(logdir):
        os.makedirs(logdir)
    for ns, alarms in _parse_alarms(content).items():
        logfile = os.path.join(logdir, f'{ns}.alarms')
        for alarm in alarms:
            with open(logfile, 'r') as f:
               fc = f.read().splitlines()
               for line in fc:
                   if line.split()[3] == alarm.split()[3]:
                       alarm = ' '.join(alarm.split()[0:4]) + ' Repeated'
                       break
            with open(logfile, 'a+') as f:
               f.write(alarm)
               f.write('\n')


def _parse_alarms(content):
    result = dict()
    timenow = datetime.now()
    timestamps = timenow.strftime("%Y-%m-%d %H:%M:%S")
    lasttimestamps = (timenow - timedelta(minutes=1)).strftime("%Y-%m-%d %H:%M:%S")
    for n in content:
        ns = n["namespace"]
        for alarm in n['alarms']:
            alarm = ', '.join(
                ['"{}": "{}"'.format(k,v) for k,v in alarm.items() if k != "expires"])
            hashstr = str(int(sha1(alarm.encode("utf-8")).hexdigest(), 16) % (10 ** 16)).rjust(20, '0')
            result.setdefault(ns, []).append(
                ' - '.join([timestamps, hashstr, alarm])
                )
    return result


def setup_file_logging(log_name, log_level='DEBUG'):
    """Setup the DEBUG to log """
    # Create logger
    logger = logging.getLogger()
    # Set FileHandler to correct filename
    fh = logging.FileHandler(log_name)
    # Set FileHadler to DEBUG level (could use called variable if needed)
    if log_level == 'INFO':
        fh.setLevel(logging.INFO)
    else:
        fh.setLevel(logging.DEBUG)
    # File output format
    file_format = logging.Formatter("%(asctime)s "
                                    "%(pathname)s::"
                                    "%(name)s::"
                                    "%(funcName)s - "
                                    "%(message)s")
    # Set format to handler
    fh.setFormatter(file_format)
    logger.addHandler(fh)


def main(input_args):
    """Main function
    """

    log = logging.getLogger()
    if log.handlers:
        log.propagate = False
        log.handlers = []

    log = logging.getLogger(__name__)

    supported_env = ["pod56", "n28", "n84", "n99"]
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--pod",
        dest="pod",
        choices=[e.lower() for e in supported_env],
        help="Pod Environment",
        metavar="POD_NAME",
        required=True
    )

    parser.add_argument(
        "--cluster",
        dest="cluster",
        help="Cluster Name",
        metavar="Cluster_NAME",
        default="eccd1"
    )


    parser.add_argument(
        "-g", "--pushgateway",
        dest="pg_root_url",
        help="Pushgateway root url.",
        metavar="PUSHGATEWAY_URL"
    )

    parser.add_argument(
        "-j", "--job-name",
        dest="jobName",
        help="Job name",
        metavar="PROMETHEUS_JOB_NAME"
    )

    parser.add_argument(
        "-i", "--job-instance-name",
        dest="jobInstanceName",
        help="Job instance name.",
        metavar="PROMETHEUS_JOB_INSTANCE_NAME"
    )

    parser.add_argument(
        "--push",
        action="store_true",
        dest="push",
        default=False,
        help="enable pushing")

    parser.add_argument(
        "--save-alarms",
        action="store_true",
        dest="save_alarms",
        default=False,
        help="enable save alarms")

    parser.add_argument(
        "--debug",
        action="store_true",
        dest="verbose",
        default=False,
        help="print more info")

    options = parser.parse_args(input_args)
    # setup logging
    if options.verbose:
        # set logging to debug
        setup_logging(logging.DEBUG)
    else:
        setup_logging(logging.INFO)

    job_name = 'dm5gcActAlarms' \
        if not options.jobName else options.jobName
    instance = '' \
        if not options.jobInstanceName else options.jobInstanceName
    log.info('Generating metrics for job {0}.'.format(job_name))
    outputs, metrics = gen_actAlarms_metrics(options.pod, options.cluster, instance=instance)
    if metrics:
        log.info('Generated metrics for job {0} done successfully.'
                 .format(job_name))
        log.debug(json.dumps(outputs))
        if options.push:
            log.debug(json.dumps(metrics, indent=4))
            if all([metrics, job_name, options.pg_root_url]):
                if push_to_pg(metrics, job_name, options.pg_root_url):
                    log.info('Pushed metrics for job {0} done successfully.'
                             .format(job_name))
                else:
                    log.error('Failed to push metrics for job {0}.'
                              .format(job_name))
        else:
            log.info(json.dumps(metrics, indent=4))
    else:
        log.error('Stopped! Generated empty metrics for job {0}.'
                  .format(job_name))

    if options.save_alarms:
        logdir = "/var/log/dm5gc_alarms/" if not options.verbose else "."
        act_alarms= [ns for ns in outputs if ns["alarms"]]
        save_to_file(act_alarms, logdir)
        log.info('Active Alarms has been saved to "{0}".'
            .format(logdir))


if __name__ == '__main__':
    main(sys.argv[1:])
