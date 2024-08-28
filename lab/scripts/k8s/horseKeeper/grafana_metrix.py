import yaml
import os
from kubernetes.client.rest import ApiException
from typing import Dict
import k8s_utils
import json
import requests
from kubernetes import client

CA_CERT = "ca.crt"
CLIENT_CERT = "cert.pem"
CLIENT_KEY = "key.pem"
SECRET_ES_CLIENT_CERT = "eric-cnom-server-searchengine-client-cert"
SECRET_PM_CLIENT_CERT = "eric-cnom-server-pm-server-client-cert"
SECRET_SIP_TLS_CA_CERT = "eric-sec-sip-tls-trusted-root-cert"
GRAFANA_NAMESPACE = "grafana"
GRAFANA_DATASOURCES_CM = "grafana-datasources"
SEARCH_ENGINE_PORT = 9200
CNF_PM_SERVER_PORT = 9089
SEARCH_ENGINE_URL_FORMAT = "{namespace}-{service_name}.ingress.{cluster}.sero.gic.ericsson.se"
K8S_CNF_SEAR_ENG_SERVICE_NAME = "eric-data-search-engine-tls"


class GrafanaMetrix(object):

    def __init__(self, grafana_ns=GRAFANA_NAMESPACE, cluster=None, k8s_client_core=None, k8s_client_netw=None,
                 logger=None):
        self.grafana_ns = grafana_ns
        self.cluster = cluster
        self.k8s_client_core = k8s_client_core
        self.k8s_client_netw = k8s_client_netw
        self.logger = logger

    def patch_cm_config(self, cnf_namespace_list, cert_output_path):
        self.logger.info("Patch configmap %s in namespace %s.", GRAFANA_DATASOURCES_CM, self.grafana_ns)
        cm_data = self.k8s_client_core.read_namespaced_config_map(name=GRAFANA_DATASOURCES_CM,
                                                                  namespace=self.grafana_ns)
        datasources = yaml.full_load(cm_data.data.get("datasource.yaml"))
        for ns in cnf_namespace_list:
            self.logger.info("Parsing secrets in namespace %s", ns)
            ca_data = k8s_utils.parse_certs_from_secret(secret_name=SECRET_SIP_TLS_CA_CERT, cnf_namespace=ns,
                                                        k8s_client=self.k8s_client_core,
                                                        logger=self.logger,
                                                        output_path=cert_output_path)
            cert_data_es = k8s_utils.parse_certs_from_secret(secret_name=SECRET_ES_CLIENT_CERT, cnf_namespace=ns,
                                                             k8s_client=self.k8s_client_core,
                                                             logger=self.logger,
                                                             output_path=cert_output_path)
            cert_data_pm = k8s_utils.parse_certs_from_secret(secret_name=SECRET_PM_CLIENT_CERT, cnf_namespace=ns,
                                                             k8s_client=self.k8s_client_core,
                                                             logger=self.logger,
                                                             output_path=cert_output_path)
            if len(ca_data) == 1 and len(cert_data_es) == 2 and len(cert_data_pm) == 2:
                datasources = self.__inject_cert_to_datasources(ca_data, cert_data_es, ns, str(SEARCH_ENGINE_PORT),
                                                                datasources)
                datasources = self.__inject_cert_to_datasources(ca_data, cert_data_pm, ns, str(CNF_PM_SERVER_PORT),
                                                                datasources)
            else:
                self.logger.error("Failed to get CA certificates or pm/search-engine client certificates for %s", ns)

        cm_data.data["datasource.yaml"] = yaml.dump(datasources)
        try:
            self.k8s_client_core.patch_namespaced_config_map(name=GRAFANA_DATASOURCES_CM, namespace=self.grafana_ns,
                                                             body=cm_data)
            self.logger.info("Patch grafana datasources config map successfully!")
        except ApiException as e:
            self.logger.error("Failed to patch grafana datasources configmap! %s.", e)

    def __inject_cert_to_datasources(self, ca, cert, cnf_namespace, service_port, ds):
        data_sources_key = "datasources"
        secure_json_data_key = "secureJsonData"
        json_data_key = "jsonData"
        for i in range(len(ds[data_sources_key])):
            if "." + cnf_namespace + ":" + service_port in ds[data_sources_key][i]["url"]:
                if json_data_key not in ds[data_sources_key][i]:
                    self.logger.warning("The field %s in %s does not exist,initialize it with {}", json_data_key,
                                        ds[data_sources_key][i]["name"])
                    ds[data_sources_key][i][json_data_key] = {}
                ds[data_sources_key][i][json_data_key]["tlsAuth"] = True
                ds[data_sources_key][i][json_data_key]["tlsAuthWithCACert"] = True
                if secure_json_data_key not in ds[data_sources_key][i]:
                    self.logger.warning("The field %s in %s does not exist,initialize it with {}", secure_json_data_key,
                                        ds[data_sources_key][i]["name"])
                    ds[data_sources_key][i][secure_json_data_key] = {}
                ds[data_sources_key][i][secure_json_data_key]["tlsCACert"] = ca.get(CA_CERT)
                ds[data_sources_key][i][secure_json_data_key]["tlsClientCert"] = cert.get(CLIENT_CERT)
                ds[data_sources_key][i][secure_json_data_key]["tlsClientKey"] = cert.get(CLIENT_KEY)
        return ds

    def create_search_engine_ingresses(self, cnf_namespace_list):
        ingress_name = K8S_CNF_SEAR_ENG_SERVICE_NAME
        for cnf_namespace in cnf_namespace_list:
            if not k8s_utils.check_namespace_exist(namespace=cnf_namespace, k8s_client=self.k8s_client_core,
                                                   logger=self.logger):
                self.logger.error("The namespace %s does not exist, skip creating the ingress.", cnf_namespace)
                return False

            # check if the ingress already exist
            try:
                fetched_ingresses = self.k8s_client_netw.list_namespaced_ingress(namespace=cnf_namespace,
                                                                                 field_selector='metadata.name='
                                                                                                + ingress_name)
            except ApiException as e:
                self.logger.error("Failed to query the ingress %s in namespace %s %s", ingress_name, cnf_namespace, e)
                return False
            if len(fetched_ingresses.items) > 0:
                self.logger.warning("Can't create ingress %s in namespace %s as it already exists, "
                                    "better to check its content!", ingress_name, cnf_namespace)
                continue

            url = SEARCH_ENGINE_URL_FORMAT.format(namespace=cnf_namespace, cluster=self.cluster,
                                                  service_name=K8S_CNF_SEAR_ENG_SERVICE_NAME)
            self.logger.info("Create ingress %s in %s, backend service:%s:%s, url:%s", ingress_name,
                             cnf_namespace, K8S_CNF_SEAR_ENG_SERVICE_NAME, SEARCH_ENGINE_PORT, url)
            annotations: Dict[str, str] = {'kubernetes.io/ingress.class': 'nginx',
                                           'nginx.ingress.kubernetes.io/backend-protocol': 'HTTPS',
                                           'nginx.ingress.kubernetes.io/ssl-passthrough': 'true'}

            metadata = client.V1ObjectMeta(annotations=annotations, namespace=cnf_namespace, name=ingress_name)
            spec_rules_http_paths_backend = client.V1IngressBackend(
                service=client.V1IngressServiceBackend(name=K8S_CNF_SEAR_ENG_SERVICE_NAME,
                                                       port=client.V1ServiceBackendPort(number=SEARCH_ENGINE_PORT)),
                resource=None)
            spec_rules_http_paths = [client.V1HTTPIngressPath(backend=spec_rules_http_paths_backend, path='/',
                                                              path_type='ImplementationSpecific')]
            spec_rules = [
                client.V1IngressRule(host=url, http=client.V1HTTPIngressRuleValue(paths=spec_rules_http_paths))]
            spec_tls = [client.V1IngressTLS(hosts=[url])]
            spec = client.V1IngressSpec(rules=spec_rules, tls=spec_tls)
            ingress_body = client.V1Ingress(api_version='networking.k8s.io/v1', kind='Ingress', metadata=metadata,
                                            spec=spec)
            try:
                self.k8s_client_netw.create_namespaced_ingress(namespace=cnf_namespace, body=ingress_body)
            except ApiException as e:
                self.logger.error("Failed to create ingress %s in namespace %s %s", ingress_name, cnf_namespace, e)
                return False

        return True

    def set_cnf_search_engine_max_buckets(self, max_buckets, cnf_namespace_list,
                                          cert_output_path):
        for cnf_namespace in cnf_namespace_list:
            self.logger.info("set search engine max_buckets for cnf %s", cnf_namespace)
            k8s_utils.parse_certs_from_secret(secret_name=SECRET_SIP_TLS_CA_CERT, cnf_namespace=cnf_namespace,
                                              k8s_client=self.k8s_client_core,
                                              logger=self.logger,
                                              output_path=cert_output_path)
            k8s_utils.parse_certs_from_secret(secret_name=SECRET_ES_CLIENT_CERT, cnf_namespace=cnf_namespace,
                                              k8s_client=self.k8s_client_core,
                                              logger=self.logger,
                                              output_path=cert_output_path)

            filename_cert = cert_output_path + os.sep + SECRET_ES_CLIENT_CERT + "-" + cnf_namespace + "-" + CLIENT_CERT
            filename_key = cert_output_path + os.sep + SECRET_ES_CLIENT_CERT + "-" + cnf_namespace + "-" + CLIENT_KEY

            url = SEARCH_ENGINE_URL_FORMAT.format(namespace=cnf_namespace, cluster=self.cluster,
                                                  service_name=K8S_CNF_SEAR_ENG_SERVICE_NAME)
            api_url = 'https://' + url + ':443' + '/_cluster/settings'
            headers = {'Content-type': 'application/json'}
            data = {"persistent": {"search": {"max_buckets": max_buckets}}}
            json_data = json.dumps(data)

            with requests.Session() as s:
                resp = s.put(url=api_url, headers=headers, data=json_data, verify=False,
                             cert=(filename_cert, filename_key))
                self.logger.info("### resp:%s", resp)
                content = json.loads(resp.content.decode('utf-8'))
                if resp.status_code == 200 and content['acknowledged']:
                    self.logger.info("Update search engine max_buckets for %s successfully.", cnf_namespace)
                else:
                    self.logger.error("Failed to update search engine max_buckets for %s, status code:%s, content:%s",
                                      cnf_namespace, resp.status_code, content)
