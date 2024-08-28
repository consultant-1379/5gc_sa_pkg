#!/lab/pccc_utils/scripts/csdp_python3_anaconda/anaconda3/bin/python -E

import os
import sys
import argparse
import subprocess
import json
import logging
import requests
from urllib import error
from urllib3 import exceptions
from urllib.parse import urljoin
from shutil import rmtree
from packaging import version

if __name__ == "__main__" and not __package__:
    p = os.path.dirname(os.path.realpath(__file__))
    if p in sys.path:
        sys.path.remove(p)
        sys.path.insert(0,
                        os.path.abspath(os.path.join(p, "../")))
    __package__ = "utils"

from .misc import is_port_open


def run_kube_cmd(kubeconfig, cmd, ns=False, timeout=60, env=None):
    """
    Execute kubectl command
    """
    log = logging.getLogger(__name__)
    if not ns:
        kc_cmd = f"kubectl --kubeconfig={kubeconfig} {cmd}"
    else:
        kc_cmd = f"kubectl --kubeconfig={kubeconfig} -n {ns} {cmd}"

    #if env is None:
        #env = {"PATH": "{0}:{1}".format("/lab/pccc_utils/scripts/src/third-party/bin", os.getenv("PATH"))}


    #log.debug("SHELL PATH var is {0}".format(env))
    log.debug("Execute kubectl command {0}".format(kc_cmd))
    p = subprocess.Popen(
        kc_cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE)
    p.wait(timeout)
    stdout, stderr = p.communicate()
    if p.poll() == 0:
        return p.communicate()[0]
    else:
        log.debug(stderr.decode())
        return False


def get_active_alerts(pod, cluster):
    """
    :param pod: e.g n28, n99, pod56 etc.
    :param cluster: eccd1, eccd3 etc.
    :return: a list for eccd alerts
    """

    log = logging.getLogger(__name__)
    kc_path = "{0}/{1}-{2}.config".format(
                  "/lab/pccc_utils/scripts/src/kubeconfig",
                  pod,
                  cluster)

    CMD1 = 'get node -l node-role.kubernetes.io/master= -o="jsonpath={.items[0].metadata.labels.ccd/version}"'
    CMD2 = 'get node -l node-role.kubernetes.io/control-plane= -o="jsonpath={.items[0].metadata.labels.ccd/version}"'
    ccd_version = run_kube_cmd(kc_path, CMD1) or run_kube_cmd(kc_path, CMD2)
    ccd_version = ccd_version.decode("utf-8")

    log.debug("CCD version is {0}".format(ccd_version))

    suffix = "seln.ete.ericsson.se" if pod == "pod56" else "sero.gic.ericsson.se"
    url = "http://monitoring-eric-pm-server.ingress.{0}-{1}.{2}".format(pod, cluster, suffix)
    if version.parse(ccd_version) < version.parse('2.22.0'):
        url = "http://monitoring-eric-pm-server.ingress.{0}-{1}.{2}".format(pod, cluster, suffix)
    elif version.parse(ccd_version) < version.parse('2.25.0'):
        url = "http://monitoring-eric-victoria-metrics-alert-server.ingress.{0}-{1}.{2}".format(pod, cluster, suffix)
    else:
        url = "http://monitoring-alertserver.ingress.{0}-{1}.{2}".format(pod, cluster, suffix)
    alert_url = urljoin(url, '/api/v1/alerts')
    log.debug(alert_url)

    res = {}
    session = requests.Session()
    s = session.get(alert_url)
    if s.__getstate__()["status_code"] == 200:
        res = s.json()
    return res


def get_active_alarms(pod, cluster):
    """
    :param pod: e.g n28, n99, pod56 etc.
    :param cluster: eccd1, eccd3 etc.
    :return: a list for eccd all namespace active alarms
    """

    log = logging.getLogger(__name__)
    suffix = "seln.ete.ericsson.se" if pod == "pod56" else "sero.gic.ericsson.se"
    kube_api = f"kubeapi.ingress.{pod}-{cluster}.{suffix}"

    res = []
    kc_path = "{0}/{1}-{2}.config".format(
                  "/lab/pccc_utils/scripts/src/kubeconfig",
                  pod,
                  cluster)
    #kubectl_opt = "--kubeconfig={0}/{1}-{2}.config".format(kc_path, pod, cluster)
    #CMD1 = "kubectl {0} get pod -ALL | egrep [[:space:]]+eric-fh-alarm-handler-[a-z0-9\-]+[[:space:]]+".format(kubectl_opt)
    CMD1 = "get pod -ALL | egrep [[:space:]]+eric-fh-alarm-handler-[a-z0-9\-]+[[:space:]]+"
    #CMD2 = "kubectl {0}".format(kubectl_opt) + " -n {0} exec {1} -c eric-fh-alarm-handler -- curl -s -k " \
    #       "{2}://localhost:{3}/ah/api/v0/alarms {4}"
    CMD2 = "exec {1} -c eric-fh-alarm-handler -- curl -s -k " \
           "{2}://localhost:{3}/ah/api/v0/alarms {4}"

    if not is_port_open(kube_api, 443):
        raise SystemExit("dial to {0} on port {1} failed.".format(kube_api, 443))
    try:
        # myScript produces continuous output, that I want to capture as it appears
        outputs =  run_kube_cmd(kc_path, CMD1)

        ns_info_dict = dict()
        port = "5005"
        proto = "http"
        for line in outputs.decode().splitlines():
            ns = line.split()[0]
            pod = line.split()[1]
            status = line.split()[3]
            addargs = ''
            GET_AHVER_CMD = 'get pod {0} -o="jsonpath={{.metadata.annotations.ericsson\.com/product-revision}}"'.format(pod)
            log.debug(GET_AHVER_CMD)
            outputs = run_kube_cmd(kc_path, GET_AHVER_CMD, ns)
            ah_version = outputs.decode().strip()
            log.debug('{0} alarm hander version is {1}'.format(ns, ah_version))
            if version.parse('7.0.0') <= version.parse(ah_version) < version.parse('7.1.0'):
                port = '5006'
                proto = 'https'
                addargs = '--cert /etc/sip-tls-client/clicert.pem --key /etc/sip-tls-client/cliprivkey.pem'
            elif version.parse(ah_version) >= version.parse('7.1.0'):
                port = '5006'
                proto = 'https'
                addargs = '--cert /run/secrets/client-cert/clicert.pem --key /run/secrets/client-cert/cliprivkey.pem'

            ns_info_dict.setdefault(ns, {})
            if len(ns_info_dict[ns]) < 1 and status == "Running":
                ns_info_dict[ns]["pod"] = pod
                ns_info_dict[ns]["status"] = status
                ns_info_dict[ns]["port"] = port
                ns_info_dict[ns]["proto"] = proto
                ns_info_dict[ns]["addargs"] = addargs

        for k, v in ns_info_dict.items():
            alarms = []
            if v:
                try:
                    outputs = run_kube_cmd(kc_path, CMD2.format(k, v["pod"], v["proto"], v["port"], v["addargs"]), k)
                    alarms = json.loads(outputs.decode().strip())
                except:
                    log.debug(CMD2.format(k, v["pod"], v["proto"], v["port"], v["addargs"]))
                    log.error("Response error from {0} on alarm handler pod.".format(k))
            res.append([k, v.get("status", "POD eric-fh-alarm-handler is NOT in Running."), alarms])
    except:
        log.warning("No eric-fh-alarm-handler pod found on the {} cluster!!!".format(cluster))
    finally:
        # cleanup
        cachedir = '.kube'
        if os.path.exists(cachedir):
            rmtree(cachedir)
    
    totAlarms = [] 
    for ns, status, alarms in res:
        totAlarms.append({"namespace": ns, "alarms": alarms, "status": status, "cluster": cluster})

    return totAlarms 


def main(input_args):
    """Main function
    """
    log = logging.getLogger()
    if log.handlers:
        log.propagate = False
        log.handlers = []
    log = logging.getLogger(__name__)

    supported_env = ["pod56", "n28", "n84", "n99", "n67", "n62", "n65", "n87", "n280"]
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-e", "--pod",
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
        metavar="CLUSTER_NAME",
        default="eccd1"
    )
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
        log.setLevel(logging.DEBUG)
    else:
        log.setLevel(logging.INFO)
    ch = logging.StreamHandler(sys.stdout)
    log.addHandler(ch)

    if logging.INFO > log.level:
        FORMAT = '%(asctime)s - %(funcName)s - %(levelname)s - %(message)s'
        logging.basicConfig(format=FORMAT)
    
    def infowrapper(msg):
        ml = len(msg)
        ol = int(100 - ml)/2
        s= '>' * int(ol) + msg + '<' * int(ol)
        return s.rjust(100, '>')
  
    log.info(infowrapper("5GC POD FH ALARM Handler alarms"))
    for d in get_active_alarms(options.pod, options.cluster):
        if d["alarms"]:
            log.info(json.dumps(d, indent=4))
    #log.info(json.dumps(get_active_alarms(options.pod, options.cluster), indent=4))
    log.info(infowrapper("ECCD Cluter Alerts"))
    log.info(json.dumps(get_active_alerts(options.pod, options.cluster), indent=4))

if __name__ == '__main__':
    main(sys.argv[1:])
