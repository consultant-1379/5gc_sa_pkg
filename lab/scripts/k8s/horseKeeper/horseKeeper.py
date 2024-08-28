#!/lab/pccc_utils/scripts/csdp_python3_venv/bin/python

import argparse
############################################################################
#                          History                                         #
# 2023-09-31 EDEKKON    Version 2.3.3                                      #
#                       Optimize the log functionality                     #
# 2023-08-30 EDEKKON    Version 2.3.2                                      #
#                       Supports 5GC CNFs health check                     #
# 2023-06-20 EDEKKON    Version 2.3.1                                      #
#                       Fix the issue that can't create ingress because of #
#                       the url doesn't contain 'cluster' info              #
# 2023-06-20 EDEKKON    Version 2.3.0                                      #
#                       Re-structure horseKeeper to several modules        #
#                       according to the functionality                     #
# 2023-06-16 EDEKKON    Version 2.2.8                                      #
#                       Support patch the grafana datasource configmap     #
#                       with TLS certificates for 5GC CNFs pm-server query #
#                       over TLS                                           #
# 2023-06-08 EDEKKON    Version 2.2.7                                      #
#                       Support the argument: --evictPods to evict some    #
#                       pods from the chosen worker nodes                  #
#                       at the end of the report.                          #
# 2023-05-15 EDEKKON    Version 2.2.6                                      #
#                       Meet the requirement: Output the location of the    #
#                       critical pods that can't be moved                  #
#                       at the end of the report.                          #
# 2023-05-05 EDEKKON    Version 2.2.5                                      #
#                       Add the recommended value description for          #
#                       argument '--excludePods'                           #
#                       Add argument --grafana-namespace to configure the  #
#                       grafana namespace                                  #
#                       for argument '--patch-grafana-ds'                  #
# 2023-04-17 EDEKKON    Version 2.2.2                                      #
#                       Support recording the critical pods on one worker  #
#                       Enhance the logging module                         #
#                       Defined dced container when collecting DECD info   #
# 2023-04-10 EDEKKON    Version 2.2.1                                      #
#                       Support the core feature of  move critical pod     #
# 2023-02-18 EDEKKON    Version 2.1                                        #
#                       Base functionality                                 #
############################################################################
import datetime
import logging
import os
import sys
import textwrap
import time

import yaml
from kubernetes import client, config

import grafana_metrix
import k8s_utils
import pods_movement
import health_check

__version__ = "v2.3.3"

K8S_CLUSTER_ENV = "~/.cnat_env.yaml"
HORSE_KEEPER_LOG_PATH = "~/horseKeeper_log"
CONFLUENCE_LINK = "Instruction: https://pdupc-confluence.internal.ericsson.com/pages/viewpage.action?pageId=248626795"


def show_logo():
    print("""
 _                         _  __                         
| |__   ___  _ __ ___  ___| |/ /___  ___ _ __   ___ _ __ 
| '_ \ / _ \| '__/ __|/ _ \ ' // _ \/ _ \ '_ \ / _ \ '__|
| | | | (_) | |  \__ \  __/ . \  __/  __/ |_) |  __/ |   
|_| |_|\___/|_|  |___/\___|_|\_\___|\___| .__/ \___|_|   
                                        |_| 
    """)


def print_confluence_url():
    # Use a breakpoint in the code line below to debug your script.
    print("#" * int(len(CONFLUENCE_LINK) + 4))
    print(f'# {CONFLUENCE_LINK} #')
    print("#" * int(len(CONFLUENCE_LINK) + 4))


def config_logging(file_name, log_path):
    logger_inst = logging.getLogger('horseKeeper')
    logger_inst.setLevel(logging.DEBUG)
    # create console handler and set level to debug
    ch = logging.StreamHandler()
    ch.setLevel(logging.INFO)

    # create formatter
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s: %(message)s')

    # add formatter to ch
    ch.setFormatter(formatter)

    # add ch to logger
    logger_inst.addHandler(ch)

    log_file_name = file_name + "-" + datetime.datetime.now().strftime('%Y%m%d%H%M%S') + ".log"

    if not os.path.exists(os.path.expanduser(log_path)):
        os.makedirs(os.path.expanduser(log_path))

    log_path = os.path.expanduser(log_path) + os.sep + log_file_name
    global HORSE_KEEPER_LOG_PATH
    HORSE_KEEPER_LOG_PATH = os.path.abspath(log_path)
    fh = logging.FileHandler(log_path)
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(formatter)
    logger_inst.addHandler(fh)
    return logger_inst


def locate_k8s_kubeconfig(cluster, file_path):
    try:
        with open(file=file_path, mode='r', encoding="utf-8") as f:
            k8s_cluster_data = yaml.full_load(f)
            cluster_list = k8s_cluster_data["cluster_kubeconfig"]
            if cluster not in cluster_list.keys():
                logger.error("Failed to locate the cluster %s \n"
                             "The candidate for the argument '-k' are :%s", cluster, list(cluster_list.keys()))
                sys.exit(1)
            else:
                return cluster_list[cluster]
    except OSError as reason:
        logger.error("Failed to open yaml file %s because %s", file_path, reason)
        return None


def get_clusters_list(file_path):
    try:
        with open(file=file_path, mode='r', encoding="utf-8") as f:
            k8s_cluster_data = yaml.full_load(f)
            cluster_list = k8s_cluster_data["cluster_kubeconfig"]
            return list(cluster_list.keys())
    except OSError as reason:
        logger.error("Failed to open yaml file %s because %s", file_path, reason)
        return None


def parse_arguments():
    arg_parser = argparse.ArgumentParser(description="version:" + __version__,
                                         usage=textwrap.dedent(
                                             '''\

                                             example:
                                             > horseKeeper -k n99-eccd1 -n sc1 ccsm1 --patch-grafana-ds --cnf-max-buckets 262143

                                             \n'''))

    group = arg_parser.add_mutually_exclusive_group(required=False)

    group.add_argument('--cluster', '-k', type=str, required=False,
                       help="the target k8s traffic cluster on which the grafana and CNFs are running. "
                            "for example n99-eccd1")

    group.add_argument('--list-clusters', '-l', action='store_true', dest='list_clusters',
                       help="list the candidate clusters for argument '-k'")

    arg_parser.add_argument('--grafana-namespace', type=str, required=False, default="grafana",
                            dest='grafana_ns',
                            help="The namespace in which the grafana is deployed.(Optional, default value is grafana)")

    arg_parser.add_argument('--cnf-namespaces', '-n', type=str, nargs="+", required=False,
                            help="the CNF namespace list, it's required by argument: -p, -b, -s, -c example:-n sc1 ccsm1")

    arg_parser.add_argument('--fivegc-cnfs-healthcheck', '-c', action='store_true', dest='fivegc_cnfs_healthcheck',
                            help="Do the health check for 5GC CNFs according to the value of argument '-n'")

    arg_parser.add_argument('--patch-grafana-ds', '-p', action='store_true', dest='patch_grafana_ds',
                            help="patch the grafana datasource configmap with the TLS certificates for pm-server "
                                 "and search-engine security query.")
    arg_parser.add_argument('--cnf-max-buckets', '-b', type=str, dest='max_buckets',
                            help="set the CNF search engine max-buckets value(create the relative ingresses "
                                 "automatically if not exist).")
    arg_parser.add_argument('--create-ingress-search-engine-tls', '-s', action='store_true',
                            dest='create_ingress_search_eng_tls',
                            help="create CNF tls search engine ingresses.")
    arg_parser.add_argument('--output', '-o', type=str, required=False,
                            help="The target path for saving the output data/log files(Optional).")

    arg_parser.add_argument('--worker-nodes-number', '-w', type=int, dest='worker_nodes_num',
                            help="Move the critical pods to the <worker-nodes-number> worker nodes, "
                                 "then these worker nodes contain all TYPE of critical pods.")

    arg_parser.add_argument('--excludePods', type=str, nargs="*", required=False,
                            help="work with '-w', input the critical pod list that can't be moved."
                                 "the recommended value:"
                                 "'pcc:eric-pc-mm-controller pcc:eric-pc-sm-controller pcg:eric-pc-up-data-plane'")

    arg_parser.add_argument('--evictPods', type=str, nargs="*", required=False,
                            help="work with '-w', input the critical pod list that need be evicted from "
                                 "the chosen worker node as they have known issues(don't have to test them)."
                                 "the input format is the same as '--excludePods'")

    arg_parser.add_argument('--record-critical-pods-on-worker', '-r', type=str, dest='worker_node_with_critical',
                            help='Save the detailed critical pods data on one worker node to a file.')

    arg_parser.add_argument('--version', '-v', action='store_true',
                            help="Show the version.")
    return arg_parser.parse_args()


def handle_log_file(app_args):
    log_file_name_segments = ["horseKeeper"]
    if app_args.fivegc_cnfs_healthcheck:
        log_file_name_segments.append("5gcHealthCheck")
    if app_args.worker_node_with_critical is not None:
        log_file_name_segments.append("RecordCriticalPods--" + args.worker_node_with_critical)
    if app_args.worker_nodes_num is not None:
        log_file_name_segments.append("MoveCriticalPods")
    if app_args.max_buckets is not None:
        log_file_name_segments.append("SetSearchEngineMaxBuckets")
    if app_args.create_ingress_search_eng_tls:
        log_file_name_segments.append("CreateIngress4SearchEngine")
    if app_args.patch_grafana_ds:
        log_file_name_segments.append("PatchGrafanaDs")
    if app_args.cluster is not None:
        log_file_name_segments.append(app_args.cluster)

    file_name = '-'.join(log_file_name_segments)

    if app_args.output is None:
        return config_logging(file_name, "./")
    else:
        return config_logging(file_name, app_args.output)


if __name__ == '__main__':
    show_logo()
    print_confluence_url()
    args = parse_arguments()
    logger = handle_log_file(args)

    if args.version:
        print(__version__)
        exit(0)

    logger.info("version:%s", __version__)
    if args.list_clusters:
        logger.info("The candidate clusters list for argument '-k':\n %s",
                    get_clusters_list(file_path=os.path.expanduser(K8S_CLUSTER_ENV)))
        exit(0)

    if args.cluster is None:
        logger.error("The argument '-k' is mandatory, The candidate clusters list is \n %s",
                     get_clusters_list(file_path=os.path.expanduser(K8S_CLUSTER_ENV)))
        exit(0)

    config_file = locate_k8s_kubeconfig(cluster=args.cluster, file_path=os.path.expanduser(K8S_CLUSTER_ENV))
    config.load_kube_config(config_file)
    client_core_v1 = client.CoreV1Api()
    client_netw_v1 = client.NetworkingV1Api()

    if args.cnf_namespaces is None and (
            args.patch_grafana_ds or args.create_ingress_search_eng_tls or args.max_buckets):
        logger.error("None of CNF namespce is picked! the candidate ones on cluster %s:\n%s", args.cluster,
                     k8s_utils.get_namespaces_list(client_core_v1))
        exit(1)

    if args.output is None:
        certs_output_path = "./certs-" + args.cluster
    else:
        certs_output_path = args.output

    grafana = None
    if args.patch_grafana_ds:
        grafana = grafana_metrix.GrafanaMetrix(grafana_ns=args.grafana_ns, cluster=args.cluster,
                                               k8s_client_core=client_core_v1,
                                               k8s_client_netw=client_netw_v1, logger=logger)
        grafana.patch_cm_config(cnf_namespace_list=args.cnf_namespaces,
                                cert_output_path=certs_output_path)
        k8s_utils.restart_pods(pod_name_prefix="grafana", namespace=args.grafana_ns, k8s_client_core=client_core_v1,
                               logger=logger)

    if args.create_ingress_search_eng_tls:
        if grafana is None:
            grafana = grafana_metrix.GrafanaMetrix(grafana_ns=args.grafana_ns, cluster=args.cluster,
                                                   k8s_client_core=client_core_v1,
                                                   k8s_client_netw=client_netw_v1, logger=logger)
        grafana.create_search_engine_ingresses(cnf_namespace_list=args.cnf_namespaces)

    if args.max_buckets is not None:

        if grafana is None:
            grafana = grafana_metrix.GrafanaMetrix(grafana_ns=args.grafana_ns, cluster=args.cluster,
                                                   k8s_client_core=client_core_v1,
                                                   k8s_client_netw=client_netw_v1, logger=logger)
        ingress_res = grafana.create_search_engine_ingresses(cnf_namespace_list=args.cnf_namespaces)
        if ingress_res:
            logger.info("Sleep 6 seconds for all the ingresses are ready.")
            time.sleep(6)
            grafana.set_cnf_search_engine_max_buckets(max_buckets=args.max_buckets,
                                                      cnf_namespace_list=args.cnf_namespaces,
                                                      cert_output_path=certs_output_path)

        else:
            logger.error("Can't set the search engine max_buckets as no ingress is available.")

    if args.worker_nodes_num is not None:
        pods_movement.PodsMovement(logger=logger).move_critical_pods(worker_nodes_number=args.worker_nodes_num,
                                                                     excluded_pods=args.excludePods,
                                                                     evict_pods=args.evictPods,
                                                                     k8s_client=client_core_v1)

    if args.worker_node_with_critical is not None:
        pods_movement.PodsMovement(logger=logger).record_critical_pods(worker_node_name=args.worker_node_with_critical,
                                                                       k8s_client=client_core_v1,
                                                                       output_path=args.output)

    if args.fivegc_cnfs_healthcheck:
        logger.info("Do health check for %s on cluster %s", args.cnf_namespaces, args.cluster)
        config_default = "~/.kube/config"
        config_backup = "~/.kube/config-bak-horseKeeper"
        os.system("cp " + config_default + " " + config_backup)
        os.system("cat " + config_file + " > " + config_default)
        logger.debug("Update %s with %s", config_default, config_file)
        health_check.HealthCheck(cnf_namespaces=args.cnf_namespaces, cluster=args.cluster, logger=logger,
                                 log_path=os.path.dirname(HORSE_KEEPER_LOG_PATH)).run_health_check_script()
        os.system("mv " + config_backup + " " + config_default)
        logger.debug("Restore the content of %s", config_default)

    if (args.max_buckets is None and not args.create_ingress_search_eng_tls and not args.patch_grafana_ds) \
            and not args.list_clusters and not args.worker_nodes_num and not args.worker_node_with_critical\
            and not args.fivegc_cnfs_healthcheck:
        logger.warning("horseKeeper is doing nothing, please consider making more arguments involved.")

    logger.info("The horseKeeper log is located in %s", HORSE_KEEPER_LOG_PATH)
