#!/lab/pccc_utils/scripts/csdp_python3_anaconda/anaconda3/bin/python

__author__ = 'Wallance Hou'
__version__ = '2.0.0'
__date__ = '2021-05-13'


import os
import sys
import requests
import json
from urllib import error
from urllib3 import exceptions
from urllib.parse import urljoin
import yaml
import random


class HostHeaderSSLAdapter(requests.adapters.HTTPAdapter):
    """Dummy DNS resolver"""
    def __init__(self, resolv_conf=None):
        super(HostHeaderSSLAdapter, self).__init__()
        self.resolv_conf = resolv_conf
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
        if self.resolv_conf and os.path.exists(self.resolv_conf):
            try:
                with open(self.resolv_conf, 'r') as f:
                    content = yaml.safe_load(f)
                for i in content["dummy_dns_resolv"]:
                    resolutions[i["name"]] = random.choice(i["ip"])
            except:
                pass
        return resolutions
 
    def resolve(self, hostname):
        # a dummy DNS resolver
        return self.resolutions.get(hostname)

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



if __name__ == '__main__':
    resolver = HostHeaderSSLAdapter("conf/host_resolv.yaml")
    print(json.dumps(resolver.resolutions, indent=4))
