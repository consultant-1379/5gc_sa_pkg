#!/usr/bin/env python

import time
import argparse
import sys
import json
import logging
from misc import push_to_pg, setup_logging
from metrics import gen_dls_metrics


def main(input_args):
    """Main function
    """
    log = logging.getLogger()
    if log.handlers:
        log.propagate = False
        log.handlers = []

    log = logging.getLogger(__name__)

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--host",
        dest="dallasHostname",
        help="Dallas Hostname",
        metavar="DALLAS_HOSTNAME",
        required=True
    )

    parser.add_argument(
        "--dlstype",
        dest="dlsType",
        help="Dallas Type",
        metavar="DALLAS_TYPE",
        required=True
    )

    parser.add_argument(
        "-g", "--pushgateway",
        dest="pg_root_url",
        help="Pushgateway root url.",
        metavar="PUSHGATEWAY_URL",
    )

    parser.add_argument(
        "-j", "--job-name",
        dest="jobName",
        help="Job name.",
        metavar="PROMETHEUS_JOB_NAME"
    )

    parser.add_argument(
        "-i", "--job-instance-name",
        dest="jobInstanceName",
        help="Job instance name.",
        metavar="PROMETHEUS_JOB_INSTANCE_NAME"
    )

    parser.add_argument(
        "-p", "--prefix",
        dest="metricPfx",
        help="Metric Prefix",
        metavar="METRIC_PREFIX"
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

    job_name = '5gcDlsKPI' \
        if not options.jobName else options.jobName
    instance = '' \
        if not options.jobInstanceName else options.jobInstanceName
    prefix = '' \
        if not options.metricPfx else options.metricPfx
    max_count = 4
    for c in range(0, max_count):
        log.info('Generating metrics for job {0}.'.format(job_name))
        dls_metrics = gen_dls_metrics(options.dallasHostname,
                                      dls_type=options.dlsType,
                                      instance=instance,
                                      prefix=prefix)
        if dls_metrics:
            log.info('Generated metrics for job {0} done successfully.'
                     .format(job_name))
            if options.push:
                log.debug(json.dumps(dls_metrics, indent=4))
                if all([dls_metrics, job_name, options.pg_root_url]):
                    if push_to_pg(dls_metrics, job_name, options.pg_root_url):
                        log.info('Pushed metrics for job {0} done '
                                 'successfully.'.format(job_name))
                    else:
                        log.error('Failed to push metrics for job {0}.'
                                  .format(job_name))
            else:
                print(json.dumps(dls_metrics, indent=4))
                break
        else:
            log.error('Stopped! Generated empty metrics for job {0}.'
                      .format(job_name))
        if c < max_count - 1:
            log.info("sleep 15s...")
            time.sleep(15)


if __name__ == '__main__':
    main(sys.argv[1:])
