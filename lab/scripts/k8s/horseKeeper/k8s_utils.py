import time
import os
from base64 import b64decode


CA_CERT = "ca.crt"
CLIENT_CERT = "cert.pem"
CLIENT_KEY = "key.pem"
K8S_POD_STATUS_RUNNING = 'Running'


def check_namespace_exist(namespace, k8s_client, logger):
    ns_list = k8s_client.list_namespace()
    if not list(map(__extract_ns, ns_list.items)).__contains__(namespace):
        logger.error("The namespace %s does not exist.", namespace)
        return False
    return True


def __extract_ns(ns_data):
    return ns_data.metadata.name


def restart_pods(pod_name_prefix, namespace, k8s_client_core, logger):
    pods = k8s_client_core.list_namespaced_pod(namespace=namespace)
    for pod in pods.items:
        if str(pod.metadata.name).startswith(pod_name_prefix):
            logger.info("Restart pod:%s in namespace %s", pod.metadata.name, namespace)
            k8s_client_core.delete_namespaced_pod(name=pod.metadata.name, namespace=namespace)

    time.sleep(10)
    check_pods_ready(pod_name_prefix=pod_name_prefix, expected_pod_status=K8S_POD_STATUS_RUNNING, namespace=namespace,
                     retry_times=3, k8s_client_core=k8s_client_core, logger=logger)


def check_pods_ready(pod_name_prefix, expected_pod_status, namespace, retry_times,
                     k8s_client_core, logger):
    counter = retry_times
    while counter > 0:
        new_pods = k8s_client_core.list_namespaced_pod(namespace=namespace)
        pods_ready_flag = True
        for pod in new_pods.items:
            if str(pod.metadata.name).startswith(pod_name_prefix):
                if expected_pod_status.lower() == "running":
                    if pod.status is None or pod.status.container_statuses is None:
                        logger.warning("It seems it's failed to get the pod information pod status:%s", pod.status)
                        pods_ready_flag = False
                        break
                    containers_ready = list(filter(lambda x: x.ready is True, pod.status.container_statuses))
                    if expected_pod_status.lower() != pod.status.phase.lower() or len(containers_ready) < len(
                            pod.status.container_statuses):
                        pods_ready_flag = False
                        logger.info("The pod %s in namespace %s is NOT Ready,status:%s(%s/%s)", pod.metadata.name,
                                    namespace,
                                    pod.status.phase, len(containers_ready), len(pod.status.container_statuses))
                        break
                    else:
                        logger.debug("The pod %s in namespace %s,status:%s(%s/%s)", pod.metadata.name,
                                     namespace,
                                     pod.status.phase, len(containers_ready), len(pod.status.container_statuses))
                elif expected_pod_status.lower() == "completed":
                    if pod.status.phase != 'Succeeded':
                        pods_ready_flag = False
                        logger.error("The pod %s is NOT Ready, status:%s", pod.metadata.name, pod.status.phase)
                        break
        counter = counter - 1
        if not pods_ready_flag:
            time.sleep(10)
        else:
            break
    if counter < 1 or counter == retry_times:
        logger.error("The pods %s-XXX in namespace %s are not ready!",
                     pod_name_prefix,
                     namespace)
        return
    logger.info("The pods %s-XXX in namespace %s are ready.", pod_name_prefix, namespace)


def parse_certs_from_secret(secret_name, cnf_namespace, k8s_client, logger, output_path):
    if not os.path.exists(output_path):
        os.makedirs(name=output_path, exist_ok=True)

    if not check_namespace_exist(namespace=cnf_namespace, k8s_client=k8s_client, logger=logger):
        logger.error("The namespace %s does not exist, skip extracting the cert data.", cnf_namespace)
        return

    secret = k8s_client.read_namespaced_secret(name=secret_name, namespace=cnf_namespace, pretty='true')
    ssl_data = {}
    if CA_CERT in secret.data:
        filename_ca = output_path + os.sep + cnf_namespace + "-" + CA_CERT
        with open(filename_ca, "w", encoding='utf-8') as f:
            f.write(b64decode(secret.data.get(CA_CERT)).decode('utf-8'))
            logger.info("The CA certificate is saved in %s", filename_ca)
            ssl_data[CA_CERT] = b64decode(secret.data.get(CA_CERT)).decode()
    elif CLIENT_CERT in secret.data:
        ssl_data[CLIENT_CERT] = b64decode(secret.data.get(CLIENT_CERT)).decode()
        ssl_data[CLIENT_KEY] = b64decode(secret.data.get(CLIENT_KEY)).decode()
        filename_cert = output_path + os.sep + secret_name + "-" + cnf_namespace + "-" + CLIENT_CERT
        filename_key = output_path + os.sep + secret_name + "-" + cnf_namespace + "-" + CLIENT_KEY
        with open(filename_cert, "w", encoding='utf-8') as f:
            f.write(b64decode(secret.data.get(CLIENT_CERT)).decode('utf-8'))
            logger.info("The client certificate is saved in %s", filename_cert)
        with open(filename_key, "w", encoding='utf-8') as f:
            f.write(b64decode(secret.data.get(CLIENT_KEY)).decode('utf-8'))
            logger.info("The private key of client certificate is saved in %s", filename_key)
    return ssl_data


def get_namespaces_list(k8s_client):
    ns_list = k8s_client.list_namespace()
    return list(map(__extract_ns, ns_list.items))


def set_k8s_nodes_scheduled_state(unschedulable, worker_node_name_list, k8s_client, logger):
    if unschedulable:
        action_name = "Cordon"
    else:
        action_name = "Uncordon"

    logger.info("%s worker nodes: %s", action_name, worker_node_name_list)

    body = {
        "spec": {
            "unschedulable": unschedulable,
        },
    }

    for name in worker_node_name_list:
        k8s_client.patch_node(name, body)

    # check worker node schedule status
    time.sleep(1)
    counter = 10
    flag = True
    while counter > 0:
        for name in worker_node_name_list:
            node = k8s_client.read_node(name)
            if (unschedulable and not node.spec.unschedulable) or \
                    (not unschedulable and node.spec.unschedulable is not None):
                flag = False
                break
        if not flag:
            logger.warning("At least one worker node is not in the wanted schedule status:%s", (not unschedulable))
            flag = True
            counter = counter - 1
            time.sleep(3)
        else:
            break

    if counter == 0:
        logger.error("Failed to %s worker nodes.", action_name.lower())
        return False

    logger.info("%s worker nodes successfully.", action_name)
    return True


def get_pod_status(pod):
    containers_ready = list(filter(lambda x: x.ready is True, pod.status.container_statuses))
    return pod.status.phase + '(' + str(len(containers_ready)) + '/' + str(len(pod.status.container_statuses)) + ')'


def get_pod_restart_count(pod):
    containers_restart_count = list(map(lambda x: x.restart_count, pod.status.container_statuses))
    return max(containers_restart_count)
