#!/lab/pccc_utils/scripts/csdp_python3_anaconda/anaconda3/bin/python

__author__ = 'Wallance Hou'
__version__ = '2.2.0'
__date__ = '2021-05-17'


import os
import sys
import requests
import json
import logging
import argparse
from urllib import error
from urllib3 import exceptions
from urllib.parse import urljoin
import yaml
import random

# supported NFs
supported_nf = ["AMF", "SMF", "PCF", "AUSF", "UDR", "UDM", "NSSF", "NEF", "BSF", "HSS", "5G_EIR", "SCP"]


class HostHeaderSSLAdapter(requests.adapters.HTTPAdapter):
    """Dummy DNS resolver"""
    def __init__(self, resolv_conf=None):
        super(HostHeaderSSLAdapter, self).__init__()
        self.resolv_conf = \
            os.path.join(os.path.dirname(__file__), "conf/host_resolv.yaml") \
                if not resolv_conf else resolv_conf
        self.resolutions = self._get_resolv_conf()

    def _get_resolv_conf(self):
        ips = [
            '5.8.6.6',  # nrf1
        ]
        resolutions = {
            'nrf1.pod56.5gc.mnc081.mcc240.3gppnetwork.org': random.choice(ips),
            'nrf1.n28.5gc.mnc081.mcc240.3gppnetwork.org': random.choice(ips),
            'nrf1.n84.5gc.mnc081.mcc240.3gppnetwork.org': random.choice(ips),
            'nrf1.n99.5gc.mnc081.mcc240.3gppnetwork.org': '5.8.6.134'
        }
        if os.path.exists(self.resolv_conf):
            try:
                content = read_file(self.resolv_conf)
                for i in content["dummy_dns_resolv"]:
                    resolutions[i["name"]] = random.choice(i["ip"])
            except:
                pass
        return resolutions
 
    def resolve(self, hostname):
        # a dummy DNS resolver
        return self.resolutions.get(hostname)

    def add_host_resolv(self, name, ip):
        self.resolutions[name] = ip
        return self

    def send(self, request, **kwargs):
        from urllib.parse import urlparse
        connection_pool_kwargs = self.poolmanager.connection_pool_kw
        result = urlparse(request.url)
        resolved_ip = self.resolve(result.hostname)
        if result.scheme == 'https' and resolved_ip:
            request.url = request.url.replace(
                'https://' + result.hostname,
                'https://' + resolved_ip,
            )
            connection_pool_kwargs['server_hostname'] = result.hostname  # SNI
            connection_pool_kwargs['assert_hostname'] = result.hostname
            # overwrite the host header
            request.headers['Host'] = result.hostname
        else:
            # theses headers from a previous request may have been left
            connection_pool_kwargs.pop('server_hostname', None)
            connection_pool_kwargs.pop('assert_hostname', None)
        return super(HostHeaderSSLAdapter, self).send(request, **kwargs)


class Nrf(object):
    """Nrf Manager"""

    def __init__(self,
                 nrf_id=None,
                 nrf_fqdn=None,
                 nrf_ip=None,
                 nrf_port=443,
                 nrf_ssl_enabled=True,
                 nrf_client_cert=None,
                 nrf_client_key=None,
                 nrf_root_ca=None,
                 nrf_domain="5gc.mnc081.mcc240.3gppnetwork.org",
                 dummy_dns_enabled=True):
        """Init"""
        self.log = logging.getLogger(self.__class__.__name__)
        self.nrf_id = nrf_id or ''
        self.nrf_fqdn = nrf_fqdn
        self.nrf_ip = nrf_ip
        self.nrf_port = nrf_port
        self.nrf_baseurl = None
        self.nrf_ssl_enabled = nrf_ssl_enabled
        self.nrf_client_cert = nrf_client_cert
        self.nrf_client_key = nrf_client_key
        self.nrf_root_ca = nrf_root_ca
        self.nrf_domain = nrf_domain
        self.nrf_location = "/nnrf-nfm/v1/"
        self.dummy_dns_enabled = dummy_dns_enabled
        self.config = None
        self.cert_path = \
                os.path.join(os.path.dirname(__file__), "conf/ssl/sbi_client")
        self.root_ca_path = \
                os.path.join(os.path.dirname(__file__), "conf/ssl/ca")

        config_file = os.path.join(os.path.dirname(__file__), "conf/config.yaml")
        if os.path.exists(config_file):
            self.config = read_file(config_file)

        # store all nf register status in NRF.
        self.all_nf_status = []

        # store all nf register status in NRF.
        self.registered_nf = []
        self.suspened_nf = []

        # define nrf url schema
        self.nrf_schema = "https" if self.nrf_ssl_enabled else "http"

        nrfs = list(self.config['nrfs'].keys())

        if self.nrf_id in nrfs:
            self.nrf_fqdn = self.config['nrfs'][self.nrf_id]['nrf_fqdn']
            self.nrf_ip = self.config['nrfs'][self.nrf_id]['nrf_ip']
            self.nrf_baseurl = \
                "{schema}://{nrf_fqdn}:{port}{location}".format(
                    schema=self.nrf_schema,
                    nrf_fqdn=self.nrf_fqdn,
                    port=self.nrf_port,
                    location=self.nrf_location
                )
            self.nrf_root_ca = \
                os.path.join(self.root_ca_path, self.config['nrfs'][self.nrf_id]['ca_cert'])
            self.nrf_client_cert = \
                os.path.join(self.cert_path, self.config['nrfs'][self.nrf_id]['client_cert'])
            self.nrf_client_key = \
                os.path.join(self.cert_path, self.config['nrfs'][self.nrf_id]['client_key'])

        # define default client cert and root ca for known pod env.
        if self.nrf_ssl_enabled and \
                (all([self.nrf_client_cert,
                      self.nrf_client_key,
                      self.nrf_root_ca]) is not True):
            self.nrf_client_key = \
                os.path.join(self.cert_path, "nrf-sbi-pythonclient.key")
            self.nrf_client_cert = \
                os.path.join(self.cert_path, "nrf-sbi-pythonclient.crt")
            self.nrf_root_ca = \
                os.path.join(self.root_ca_path, "ca.crt")

        # dummy dns for requests
        # NOTE: dummy dns conf file is located in conf/host_resolv.yaml.
        if self.dummy_dns_enabled:
            self.resolver = HostHeaderSSLAdapter()

        # define nrf_baseurl and add dummy dns record when nrf_fqdn and ip
        # are given.
        if self.nrf_fqdn and self.nrf_ip:
            self.resolver.add_host_resolv(self.nrf_fqdn, self.nrf_ip)
            self.nrf_baseurl = "{schema}://{fqdn}:{port}{location}".format(
                schema=self.nrf_schema,
                fqdn=self.nrf_fqdn,
                port=self.nrf_port,
                location=self.nrf_location)
            self.log.debug("Generated baseurl {0}".format(self.nrf_baseurl))

        if self.nrf_baseurl is None:
            self.log.error(f"invalid nrf id provided in -e option, supported nrf id: {nrfs}")
            sys.exit(1)

        self.log.info(f"NRF Agent: {self.nrf_fqdn}:{self.nrf_ip}:{self.nrf_port}")


    def query_nf_status(self, enable_print_all_outputs=False):
        """Query NF status from NRF"""
        nf_status_all = []
        nf_status = []
        resp = self._get_http_resp(self.nrf_baseurl, "nf-instances")
        for item in resp["_links"]["item"]:
            resp = self._get_http_resp(item["href"])
            nf_status_all.append(resp)
            nf_info = dict()
            nf_info["nfType"] = resp["nfType"]
            nf_info["nfStatus"] = resp["nfStatus"]
            nf_info["FQDN"] = resp["fqdn"]

            if nf_info["nfStatus"] == "SUSPENDED":
                self.suspened_nf.append(nf_info["nfType"])
            else:
                self.registered_nf.append(nf_info["nfType"])
            self.log.debug("Query NF status response: %s", resp)
            for svc in resp.get("nfServices", []):
                nf_info.setdefault("nfServices", []).append(
                    {"nfServiceStatus": svc["nfServiceStatus"],
                     "nfServiceName": svc["serviceName"]})
            nf_status.append(nf_info)
        self.all_nf_status = nf_status_all
        return nf_status_all if enable_print_all_outputs else nf_status

    def check_nf_details(self, nf_list):
        """Return nf detailed information"""
        nf_details_list = []
        nf_list = [i.upper() for i in nf_list]
        for nf in self.all_nf_status:
            if nf["nfType"].upper() in nf_list:
                nf_details_list.append(nf)
        return nf_details_list

    def delete_nf(self, nf_list, status="SUSPENDED"):
        """Delete NF(s)"""
        count = 0
        for nf_type in nf_list:
            resp = \
                self._get_http_resp(self.nrf_baseurl,
                                    "nf-instances?nf-type={}".format(nf_type))
            if resp['_links']['item']:
                for item in resp['_links']['item']:
                    resp = self._get_http_resp(item['href'])
                    if resp.get('nfStatus') == status:
                        self.log.info(
                            'Deleting {0} {1} with nfInstanceId: {2}'
                                .format(status, nf_type, resp.get('nfInstanceId')))
                        frag = \
                            "nf-instances/{}".format(resp.get("nfInstanceId"))
                        self._delete_http(self.nrf_baseurl, frag)
                        count += 1
        self.log.info('All the {0} {1} NFs is deleted.'.format(count, status))

    def _get_http_resp(self, baseurl, fragment=""):
        url = urljoin(baseurl, fragment)
        session = requests.Session()
        if self.nrf_ssl_enabled and self.dummy_dns_enabled:
            session.mount('https://', self.resolver)
        result = []
        self.log.debug("Get response for URL {0}".format(url))
        try:
            if self.nrf_ssl_enabled:
                result = session.get(
                    url,
                    cert=(self.nrf_client_cert, self.nrf_client_key),
                    verify=self.nrf_root_ca
                ).json()
            else:
                result = session.get(url).json()
        except Exception as e:
            raise SystemExit(self.log.error(e))
        finally:
            session.close()
        return result

    def _delete_http(self, baseurl, fragment=""):
        url = urljoin(baseurl, fragment)
        session = requests.Session()
        if self.nrf_ssl_enabled and self.dummy_dns_enabled:
            session.mount('https://', self.resolver)
        self.log.debug("Delete for URL {0}".format(url))
        try:
            if self.nrf_ssl_enabled:
                session.delete(
                    url,
                    cert=(self.nrf_client_cert, self.nrf_client_key),
                    verify=self.nrf_root_ca
                )
            else:
                session.delete(url)
        except Exception as e:
            raise SystemExit(self.log.error(e))
        finally:
            session.close()


def _pretty_json(content):
    """pretty json outputs"""
    return json.dumps(content, indent=2)


def main(input_args):
    """Main function
    """
    log = logging.getLogger()
    if log.handlers:
        log.propagate = False
        log.handlers = []

    parser = argparse.ArgumentParser()
    group1 = parser.add_mutually_exclusive_group(required=True)

    group1.add_argument(
        "-e", "--nrf_id",
        dest="nrf_id",
        type=str.lower,
        help="Pod name or NRF ID",
        metavar="NRF_ID"
    )
    group1.add_argument(
        "-n", "--nrf-fqdn",
        dest="nrf_fqdn",
        type=str.lower,
        help="NRF FQDN",
        metavar="NRF_FQDN",
    )
    parser.add_argument(
        "-i", "--nrf-ip",
        dest="nrf_ip",
        type=str.lower,
        help="NRF IP",
        metavar="NRF_IP"
    )
    parser.add_argument(
        "-k", "--client-key",
        help="Path of client key file",
        metavar="CLIENT_KEY_FILE"
    )
    parser.add_argument(
        "-c", "--client-cert",
        help="Path of client cert file",
        metavar="CLIENT_CERT_FILE"
    )
    parser.add_argument(
        "-r", "--root-ca",
        help="Path of root ca file",
        metavar="CLIENT_ROOTCA_FILE"
    )
    parser.add_argument(
        "--nf-type",
        dest="nf_types",
        nargs="+",
        choices=supported_nf,
        type=str.upper,
        help="The NF(s) to be check for their detailed status"
    )
    parser.add_argument(
        "-D",
        "--delete",
        default=False,
        action="store_true",
        help="Delete the suspended NF(s) from the specific NF(s)",
    )
    parser.add_argument(
        "-a", "--show-all",
        action="store_true",
        dest="printAll",
        default=False,
        help="enable print all outputs")

    parser.add_argument(
        "--debug",
        action="store_true",
        dest="verbose",
        default=False,
        help="print more info")

    options = parser.parse_args(input_args)
    if options.nrf_ip and (options.nrf_fqdn is None):
        parser.error("-i/--nrf-ip requires -n/--nrf-fqdn.")

    # setup logging
    if options.verbose:
        # set logging to debug
        log.setLevel(logging.DEBUG)
    else:
        log.setLevel(logging.INFO)
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(
        logging.Formatter('%(levelname)-8s > %(asctime)s : %(message)s',
                          '%Y-%m-%d %H:%M:%S')
    )
    log.addHandler(ch)

    nrf = Nrf(nrf_id=options.nrf_id,
              nrf_fqdn=options.nrf_fqdn,
              nrf_ip=options.nrf_ip,
              nrf_client_cert=options.client_cert,
              nrf_client_key=options.client_key,
              nrf_root_ca=options.root_ca
             )
    result = nrf.query_nf_status(enable_print_all_outputs=options.printAll)
    if options.nf_types:
        if options.delete:
            nrf.delete_nf(options.nf_types)
            return
        else:
            log.info(_pretty_json(nrf.check_nf_details(options.nf_types)))
    else:
        log.info('Summarized registered NFs on NRF Agent:\n'+'\n'+'\n'.join([str(i) for i in result])+'\n')
    # summary
    log.info("Total {0} registered NF(s) list: {1}".format(len(nrf.registered_nf), nrf.registered_nf))
    if nrf.suspened_nf:
        log.warning("Total {0} suspened NF(s) list: {1}".format(len(nrf.suspened_nf), nrf.suspened_nf))


def read_file(file):
    content = ''
    with open(file, 'r') as f:
        content = yaml.safe_load(f)
    return content


if __name__ == '__main__':
    main(sys.argv[1:])
