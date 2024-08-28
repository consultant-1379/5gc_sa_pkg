#!/usr/bin/env python

import argparse
import sys
import json
from misc import push_to_pg, setup_logging
from metrics import gen_nfStatus_metrics
import logging


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
        "--nrf-id",
        dest="nrf_id",
        help="NRF ID",
        metavar="NRF_ID",
        required=True
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

    job_name = 'dm5gcNrfQuery' \
        if not options.jobName else options.jobName
    instance = '' \
        if not options.jobInstanceName else options.jobInstanceName
    log.info('Generating metrics for job {0}.'.format(job_name))
    nrf_metrics = gen_nfStatus_metrics(options.nrf_id, instance=instance)
    if nrf_metrics:
        log.info('Generated metrics for job {0} done successfully.'
                 .format(job_name))
        if options.push:
            log.debug(json.dumps(nrf_metrics, indent=4))
            if all([nrf_metrics, job_name, options.pg_root_url]):
                if push_to_pg(nrf_metrics, job_name, options.pg_root_url):
                    log.info('Pushed metrics for job {0} done successfully.'
                             .format(job_name))
                else:
                    log.error('Failed to push metrics for job {0}.'
                              .format(job_name))
        else:
            print(json.dumps(nrf_metrics, indent=4))
    else:
        log.error('Stopped! Generated empty metrics for job {0}.'
                  .format(job_name))


if __name__ == '__main__':
    main(sys.argv[1:])
