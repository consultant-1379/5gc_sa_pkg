## NOT USED ANYMORE 2023-02-10



#!/usr/bin/env python

import argparse
import os
import sys
import json
import logging
from datetime import datetime, timedelta
import time
from misc import push_to_pg, setup_logging
from metrics import gen_redis_metrics


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


def decorator(func):
    def wrap_the_function(*args, **kwargs):
        for i in range(0, 1):
            func(*args, **kwargs)
            time.sleep(30)
            func(*args, **kwargs)
    return wrap_the_function


@decorator
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
        "-n", "--namespace",
        dest="namespace",
        help="Namespace",
        metavar="NAMESPACE",
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

    job_name = 'CheckRedis' \
        if not options.jobName else options.jobName
    instance = '' \
        if not options.jobInstanceName else options.jobInstanceName
    log.info('Generating metrics for job {0}.'.format(job_name))

    metrics = gen_redis_metrics(options.pod, options.cluster, options.namespace, instance=instance)
    if metrics:
        log.info('Generated metrics for job {0} done successfully.'
                 .format(job_name))
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


if __name__ == '__main__':
    main(sys.argv[1:])

