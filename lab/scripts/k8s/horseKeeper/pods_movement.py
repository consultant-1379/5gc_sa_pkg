import os
from getpass import getpass, getuser
from bs4 import BeautifulSoup
import urllib.request
import base64
from itertools import chain
import copy
import datetime
import time
import re
import k8s_utils

TESTED_CRITICAL_PODS_FILE_NAME = 'testedCriticalPods.log'
CRITICAL_PODS_JIRA_URL = "https://pdupc-jira.internal.ericsson.com/browse/PCVTC-3346"


class PodsMovement(object):

    def __init__(self, logger):
        self.logger = logger

    def __sleep(self, seconds):
        self.logger.info("Wait for %s seconds.", seconds)
        time.sleep(seconds)

    def __get_critical_pods_from_jira(self):

        self.logger.info("Fetching critical pods from jira(input EID password) %s", CRITICAL_PODS_JIRA_URL)
        user = getuser()
        password = getpass()
        request = urllib.request.Request(CRITICAL_PODS_JIRA_URL)
        base64string = base64.b64encode(bytes('%s:%s' % (user, password), 'ascii'))
        request.add_header("Authorization", "Basic %s" % base64string.decode('utf-8'))
        result = urllib.request.urlopen(request)
        html = result.read()

        soup = BeautifulSoup(html, features="html.parser")

        # interesting info has td (table division?)
        criticalPods = []
        product = pod = ""
        items = soup.find_all('td')
        increment = False
        for i in range(5, len(soup.find_all('td'))):
            # jira has been updated with a new column with the old name of the pod
            # probably this code could be nicer
            if increment:
                i = i + 2
                increment = False
            # only the cell with product has a dot
            if "." in items[i].text:
                product = items[i + 1].text
                # product = re.search("[0-9]+.\s([A-Z]+)", items[i+1].text).group(1).lower()
            # all critical pods start with "eric"
            if "eric" in items[i].text:
                pod = items[i].text
                increment = True
            if product and pod:
                criticalPods.append((product.lower(), pod))
                product = pod = ""

        self.logger.info("Number of critical pods from Jira: %s", len(criticalPods))
        self.logger.debug("The critical pods list: %s", criticalPods)
        return criticalPods

    def __do_critical_pods_data_cleaning(self, excluded_pods, critical_pods,
                                         tested_critical_pods_file_path=os.curdir + os.sep + TESTED_CRITICAL_PODS_FILE_NAME):
        if os.path.exists(tested_critical_pods_file_path):
            self.logger.info("Filter out the tested critical pods from the overall critical pod list based on %s.",
                             os.path.abspath(tested_critical_pods_file_path))
            with open(tested_critical_pods_file_path, mode='r') as f:
                line = f.readline().strip('\n')
                while line:
                    result = re.match(r'(\S+):(\S+)', line)
                    if result is not None:
                        self.logger.warning("Remove the tested critical pods from the overall list:%s",
                                            (result.group(1), result.group(2)))
                        critical_pods.remove((result.group(1), result.group(2)))
                    line = f.readline().strip('\n')
        else:
            self.logger.info("None of critical pods has been tested as %s does not exist.",
                             tested_critical_pods_file_path)
        if excluded_pods is not None:
            sep = ':'
            for excluded_pod in excluded_pods:
                if sep not in excluded_pod:
                    self.logger.error(
                        "Wrong value format for argument '--excludePods', content should be like pcg:eric-pc-up-data-plane")
                    exit(1)
                namespace = excluded_pod.split(sep)[0]
                pod_prefix = excluded_pod.split(sep)[1]
                if (namespace, pod_prefix) in critical_pods:
                    self.logger.warning("Exclude critical pod:%s, would not move it.", (namespace, pod_prefix))
                    critical_pods.remove((namespace, pod_prefix))
                else:
                    self.logger.warning("The pod %s to exclude is not in the critical pod list", excluded_pod)

        self.logger.info("Number of critical pods after removing the tested and excluded pods:%s",
                         len(critical_pods))
        self.logger.debug("The critical pods list after removing the tested and excluded pods: %s", critical_pods)

    def __remove_un_deployed_critical_pods(self, critical_pods, all_pods):
        all_pods_tidy = list(map(lambda pod: (pod.metadata.namespace.lower(), pod.metadata.name), all_pods.items))
        critical_pod_backup = copy.deepcopy(critical_pods)
        for critical_pod in critical_pod_backup:
            found = False
            for pod_tidy in all_pods_tidy:
                if str(pod_tidy[0]).startswith(critical_pod[0]) and str(pod_tidy[1]).startswith(critical_pod[1]):
                    found = True
                    break
            if not found:
                self.logger.warning("Remove the pod %s item from the planned critical pod list "
                                    "as it's not deployed on target k8s cluster.", critical_pod)
                critical_pods.remove(critical_pod)
        self.logger.info("Number of critical pods after removing the un-deployed pods:%s", len(critical_pods))
        self.logger.debug("The critical pods list after removing the un-deployed pods:%s", critical_pods)

    def __delete_running_pods(self, critical_pods_to_move, all_pods, k8s_client):
        move_counter = 0
        for item in critical_pods_to_move:
            for pod in all_pods.items:
                pod_name = pod.metadata.name
                namespace = pod.metadata.namespace.lower()
                k8s_resource_kind = pod.metadata.owner_references[0].kind
                if str(namespace).startswith(item[0]) and str(pod_name).startswith(item[1]):
                    if k8s_resource_kind != 'DaemonSet':
                        if 'eric-pc-up-data-plane' not in pod_name:
                            self.logger.info("Move pod:%s in namespace:%s", pod_name, namespace)
                            move_counter = move_counter + 1
                            k8s_client.delete_namespaced_pod(pod_name, namespace)
                            if k8s_resource_kind == "StatefulSet":
                                self.__sleep(45)
                            else:
                                self.__sleep(10)
                            k8s_utils.check_pods_ready(pod_name_prefix=item[1],
                                                       expected_pod_status=k8s_utils.K8S_POD_STATUS_RUNNING,
                                                       namespace=namespace, retry_times=60,
                                                       k8s_client_core=k8s_client,
                                                       logger=self.logger)
                        else:
                            self.logger.warning(
                                "Don't have to move pod eric-pc-up-data-plane as they are deployed in seperate pool")

                    break

        return move_counter

    def __evict_critical_pods(self, critical_pods, worker_node_name_list, k8s_client):
        if critical_pods is None:
            return

        self.logger.info("Evict critical pods:%s from the chosen worker nodes:%s", critical_pods, worker_node_name_list)
        all_pods = k8s_client.list_pod_for_all_namespaces()
        cordon_suc = k8s_utils.set_k8s_nodes_scheduled_state(unschedulable=True,
                                                             worker_node_name_list=worker_node_name_list,
                                                             k8s_client=k8s_client, logger=self.logger)
        if not cordon_suc:
            self.logger.error("Failed to cordon worker nodes:%s", worker_node_name_list)
            exit(1)

        for critical_pod in critical_pods:
            result = re.match(r'(\S+):(\S+)', critical_pod)
            if result is None:
                self.logger.error("The format of critical pod to evict:%s is wrong, skip this one.", critical_pod)
                continue
            cnf_name = result.group(1)
            critical_pod_prefix = result.group(2)
            for pod in all_pods.items:
                worker_node_name = pod.spec.node_name
                pod_name = pod.metadata.name
                namespace = pod.metadata.namespace.lower()
                k8s_resource_kind = pod.metadata.owner_references[0].kind
                if str(namespace).startswith(cnf_name) and str(pod_name).startswith(critical_pod_prefix) \
                        and worker_node_name in worker_node_name_list:
                    k8s_client.delete_namespaced_pod(pod_name, namespace)
                    self.logger.debug("Evicting pod:%s--%s from worker node:%s", namespace, pod_name, worker_node_name)
                    if k8s_resource_kind == "StatefulSet":
                        self.__sleep(45)
                    else:
                        self.__sleep(10)
                    k8s_utils.check_pods_ready(pod_name_prefix=critical_pod_prefix,
                                               expected_pod_status=k8s_utils.K8S_POD_STATUS_RUNNING,
                                               namespace=namespace, retry_times=60,
                                               k8s_client_core=k8s_client,
                                               logger=self.logger)
        k8s_utils.set_k8s_nodes_scheduled_state(unschedulable=False, worker_node_name_list=worker_node_name_list,
                                                k8s_client=k8s_client, logger=self.logger)

    def move_critical_pods(self, worker_nodes_number, excluded_pods, evict_pods, k8s_client):
        """ move_critical_pods

            Move the critical pods to the <worker_nodes_number> woker nodes by cordon/uncordon and delete pod

            :param worker_nodes_number: the planned worker nodes number on which run all the critical pods
            :param excluded_pods: the critical pods that don't have to move
            :param evict_pods: the critical pods that need be evicted from the chosen worker nodes
                                as they have known issues don't have to test
                                list of <cnf-name>:<critical-pod-name>
            :param CoreV1Api k8s_client: The k8s client sends kubectl commands to k8s cluster
            :return:
            """
        # List of tuple (<NAMESPACE>, <POD-PREFIX>)
        critical_pods = self.__get_critical_pods_from_jira()
        self.logger.info("Get the pods of all the namespace in k8s cluster, it may take several seconds.")
        all_pods = k8s_client.list_pod_for_all_namespaces()

        self.__do_critical_pods_data_cleaning(excluded_pods=excluded_pods, critical_pods=critical_pods)
        self.__remove_un_deployed_critical_pods(critical_pods=critical_pods, all_pods=all_pods)
        picked_worker_nodes = self.__fetch_worker_nodes_with_critical_pods(worker_nodes_number, critical_pods, all_pods)
        critical_pods_to_move = self.__get_critical_pods_to_move(picked_worker_nodes=picked_worker_nodes,
                                                                 critical_pods=critical_pods)

        if len(critical_pods_to_move) < 1:
            self.logger.info("No need to move pods as the picked worker nodes have all the wanted critical pods.")
            self.__print_picked_worker_nodes(excluded_pods=excluded_pods, all_pods_in_whole_cluster=all_pods,
                                             picked_worker_nodes=picked_worker_nodes)
            self.__evict_critical_pods(critical_pods=evict_pods,
                                       worker_node_name_list=list(map(lambda x: x[0], picked_worker_nodes)),
                                       k8s_client=k8s_client)

        else:
            # get all the k8s nodes from the target k8s cluster
            all_k8s_nodes = k8s_client.list_node().items
            picked_worker_node_name_list = list(map(lambda x: x[0], picked_worker_nodes))
            k8s_node_name_list = list(map(lambda x: x.metadata.name, all_k8s_nodes))
            k8s_node_name_list_to_cordon = list(filter(
                lambda x: x not in picked_worker_node_name_list and not x.__contains__('master'), k8s_node_name_list))

            cordon_suc = k8s_utils.set_k8s_nodes_scheduled_state(unschedulable=True,
                                                                 worker_node_name_list=k8s_node_name_list_to_cordon,
                                                                 k8s_client=k8s_client, logger=self.logger)
            if not cordon_suc:
                self.logger.error("Can't move critical pods as failed to cordon worker nodes")
                exit(1)

            self.__sleep(5)
            self.logger.info("Start moving %s critical pods to worker nodes:%s", len(critical_pods_to_move),
                             picked_worker_node_name_list)
            move_counter = self.__delete_running_pods(critical_pods_to_move=critical_pods_to_move, all_pods=all_pods,
                                                      k8s_client=k8s_client)

            self.__sleep(10)
            k8s_utils.set_k8s_nodes_scheduled_state(unschedulable=False,
                                                    worker_node_name_list=k8s_node_name_list_to_cordon,
                                                    k8s_client=k8s_client, logger=self.logger)

            self.logger.info("Get the pods of all the namespace in k8s cluster, it may take several seconds.")
            all_pods_after_move = k8s_client.list_pod_for_all_namespaces()
            picked_worker_nodes = self.__fetch_worker_nodes_with_critical_pods(worker_nodes_number, critical_pods,
                                                                               all_pods_after_move)
            critical_pods_left = self.__get_critical_pods_to_move(picked_worker_nodes=picked_worker_nodes,
                                                                  critical_pods=critical_pods)
            if len(critical_pods_left) < 1:
                self.logger.info("%s critical pods have been moved successfully.", move_counter)
                self.logger.info("Congratulations! The picked worker nodes have all the critical pods")
                self.__print_picked_worker_nodes(excluded_pods=excluded_pods, all_pods_in_whole_cluster=all_pods_after_move,
                                                 picked_worker_nodes=picked_worker_nodes)
                self.__evict_critical_pods(critical_pods=evict_pods, worker_node_name_list=picked_worker_node_name_list,
                                           k8s_client=k8s_client)
            else:
                self.logger.error(
                    "Too bad, there are still some critical pods out of the picked %s worker nodes:\n %s",
                    worker_nodes_number, critical_pods_left)

    def __print_picked_worker_nodes(self, excluded_pods, all_pods_in_whole_cluster, picked_worker_nodes):
        """
        print the picked worker node list
        :param excluded_pods: list of string like "<namespace>:<critical_pods_prefix>"
        :param all_pods_in_whole_cluster: All the running pods list from the target k8s cluster
        :param picked_worker_nodes: List, [(WORKER-NODE-NAME>,[(<NAMESPACE>, <POD-PREFIX>),...]),...]
        :return:
        """
        excluded_pods_formatted = []
        worker_node_name_list = list(map(lambda x: x[0], picked_worker_nodes))
        if excluded_pods is not None:
            for excluded_pod in excluded_pods:
                result = re.match(r'(\S+):(\S+)', excluded_pod)
                if result is not None:
                    excluded_pods_formatted.append((result.group(1), result.group(2)))
                else:
                    self.logger.error(
                        "Wrong value format for argument '--excludePods', content should be like pcg:eric-pc-up-data-plane")
                    exit(1)

            self.logger.info("The worker nodes with all the critical pods except the 'excluded' ones:\n %s",
                             worker_node_name_list)
            worker_nodes_with_excluded_pods = self.__get_worker_nodes_with_critical_pods(excluded_pods_formatted,
                                                                                         all_pods_in_whole_cluster)
            for item in worker_nodes_with_excluded_pods.keys():
                self.logger.info("The worker node %s with the excluded critical pods:%s running", item,
                                 worker_nodes_with_excluded_pods[item])

            # add the worker nodes with the excluded critical pods to final picked node list
            for i in excluded_pods_formatted:
                # For saving the worker node list that contains one specific critical pod type
                worker_list_with_specific_critical = []
                for item in worker_nodes_with_excluded_pods.keys():
                    if i in worker_nodes_with_excluded_pods[item]:
                        worker_list_with_specific_critical.append(item)
                added_flag = False
                for w in worker_list_with_specific_critical:
                    if w in worker_node_name_list:
                        added_flag = True
                        break
                if not added_flag and len(worker_list_with_specific_critical) > 0:
                    worker_node_name_list.append(worker_list_with_specific_critical[0])

        self.logger.info("The total picked worker node list to reboot:\n %s", worker_node_name_list)

    def __get_worker_nodes_with_critical_pods(self, critical_pods, all_pods):
        """get_worker_nodes_with_critical_pods

        get the worker nodes with critical pods on them

        :param all_pods: All the running pods list from the target k8s cluster
        :param List critical_pods: List of tuple (<NAMESPACE>, <POD-PREFIX>)
        :return: Dict, {WORKER-NODE-NAME>:[(<NAMESPACE>, <POD-PREFIX>),...],...}
        """
        worker_node_dict = {}

        for pod in all_pods.items:
            worker_node_name = pod.spec.node_name
            pod_name = pod.metadata.name
            namespace = pod.metadata.namespace.lower()
            for critical_pod in critical_pods:
                if str(namespace).startswith(critical_pod[0]) and str(pod_name).startswith(critical_pod[1]):
                    if worker_node_name not in worker_node_dict.keys():
                        worker_node_dict[worker_node_name] = [critical_pod]
                    elif critical_pod not in worker_node_dict[worker_node_name]:
                        worker_node_dict[worker_node_name].append(critical_pod)

        for item in worker_node_dict.keys():
            self.logger.debug("Node name:%s critical-pod-num: %s, details:%s", item, len(worker_node_dict[item]),
                              worker_node_dict[item])

        return worker_node_dict

    def __fetch_worker_nodes_with_critical_pods(self, worker_nodes_number, critical_pods, all_pods):
        """fetch_worker_nodes_with_most_critical_pods

        list the top N worker nodes with most critical pods

        :param worker_nodes_number: the planned worker nodes number on which run all the critical pods
        :param all_pods: All the running pods list from the target k8s cluster
        :param List critical_pods: List of tuple (<NAMESPACE>, <POD-PREFIX>)
        :return: List, [(WORKER-NODE-NAME>,[(<NAMESPACE>, <POD-PREFIX>),...]),...]
                 return the picked worker nodes with the critical pods info.
        """
        worker_node_with_critical_dict = self.__get_worker_nodes_with_critical_pods(critical_pods=critical_pods,
                                                                                    all_pods=all_pods)
        worker_node_dict_sorted = sorted(worker_node_with_critical_dict.items(), key=lambda x: len(x[1]), reverse=True)

        if len(worker_node_dict_sorted) <= worker_nodes_number:
            res = worker_node_dict_sorted
        else:
            res = worker_node_dict_sorted[:worker_nodes_number]
        for item in res:
            self.logger.info("The picked worker node:%s with %s critical pods.", item[0], len(item[1]))
            self.logger.debug("The picked worker node:%s with the critical pods:%s", item[0], item[1])
        return res

    def __get_critical_pods_to_move(self, picked_worker_nodes, critical_pods):
        """get_critical_pods_to_move

        get the critical pods need to move, the critical pods is from the jira case, not the ones that are running on
        k8s

        :param List picked_worker_nodes: List of (WORKER-NODE-NAME>,[(<NAMESPACE>, <POD-PREFIX>),...])
        :param List critical_pods: List of tuple (<NAMESPACE>, <POD-PREFIX>), it's from the jira case
        :return: List , the List of tuple (<NAMESPACE>, <POD-PREFIX>)
        """

        critical_pods_to_move = []
        critical_pods_in_place = set(list(chain.from_iterable(list(map(lambda x: x[1], picked_worker_nodes)))))

        self.logger.info("The number of critical pods that no need to move is %s.", len(critical_pods_in_place))
        self.logger.debug("The critical pods that no need to move:%s", critical_pods_in_place)
        for critical_pod in critical_pods:
            if critical_pod not in critical_pods_in_place:
                critical_pods_to_move.append(critical_pod)
        self.logger.info("critical_pods_to_move %s", critical_pods_to_move)
        return critical_pods_to_move

    def record_critical_pods(self, worker_node_name, k8s_client, output_path):

        critical_pods = self.__get_critical_pods_from_jira()
        if output_path is None:
            file_path = os.path.abspath(os.curdir + os.sep + TESTED_CRITICAL_PODS_FILE_NAME)
        else:
            file_path = output_path + os.sep + TESTED_CRITICAL_PODS_FILE_NAME

        self.__do_critical_pods_data_cleaning([], critical_pods, tested_critical_pods_file_path=file_path)

        # To avoid the issue: The wrong critical pod 'pod1' would be picked if the pod like 'pod1-plus-xxx-xxx'
        #  is running and meanwhile two critical pods 'pod1' and 'pod1-plus' belong to the same CNF are in the
        #  critical_pods list
        critical_pods_sorted = list(sorted(critical_pods, key=lambda x: len(x[1]), reverse=True))
        self.logger.info("Get the pods of all the namespace in k8s cluster, it may take several seconds.")
        all_pods = k8s_client.list_pod_for_all_namespaces()
        pods_on_worker = []
        critical_pods_on_worker = []
        self.logger.info("The total pods number:%s, worker_node_name:%s", len(all_pods.items), worker_node_name)
        for pod in all_pods.items:
            pod_name = pod.metadata.name
            namespace = pod.metadata.namespace.lower()
            if pod.spec.node_name == worker_node_name:
                for critical_pod in critical_pods_sorted:
                    if str(namespace).startswith(critical_pod[0]) and str(pod_name).startswith(critical_pod[1]) \
                            and critical_pod not in critical_pods_on_worker:
                        critical_pods_on_worker.append(critical_pod)
                        self.logger.debug("critical namespace:%s pod-prefix:%s", critical_pod[0], critical_pod[1])
                        break
                pods_on_worker.append(pod)

        if len(critical_pods_on_worker) > 0:
            with open(file=file_path, mode='a', encoding='utf-8') as f:
                f.write(datetime.datetime.now().strftime('timestamp %Y-%m-%d %H:%M:%S.%f\n'))
                f.write("###### Critical pods ######\n")
                for critical_pod in critical_pods_on_worker:
                    f.write(critical_pod[0] + ':' + critical_pod[1] + '\n')
                    self.logger.info("Saving critical pod %s on %s to file", critical_pod, worker_node_name)
                f.close()
                self.logger.info("Save critical pods on worker node %s to %s successfully", worker_node_name, file_path)
                self.__save_pods_data_to_file(pod_list=pods_on_worker, file_path=file_path)
                self.logger.info("Next step would be reboot %s manually, Good luck!", worker_node_name)
        else:
            self.logger.info("On %s,There is not any critical pods or the critical pods on it have been tested. ",
                             worker_node_name)
            self.__save_pods_data_to_file(pod_list=pods_on_worker, file_path=file_path)

    def __save_pods_data_to_file(self, pod_list, file_path):
        if len(pod_list) == 0:
            self.logger.warning("No any pods gotten.")
            return
        K8S_POD_PRINT_FORMAT = "{namespace:<15}{pod_name:<70}{status:^15}{restarts:^15}{ip:^20}{node}\n"
        with open(file=file_path, mode='a', encoding='utf-8') as f:
            f.write('###### Detailed pods information ######\n')
            f.write(K8S_POD_PRINT_FORMAT.format(namespace='NAMESPACE', pod_name='NAME',
                                                status='STATUS', restarts='RESTARTS',
                                                ip='IP', node='NODE'))
            for pod in pod_list:
                f.write(
                    K8S_POD_PRINT_FORMAT.format(namespace=pod.metadata.namespace, pod_name=pod.metadata.name,
                                                status=k8s_utils.get_pod_status(pod),
                                                restarts=k8s_utils.get_pod_restart_count(pod),
                                                ip=pod.status.pod_ip, node=pod.spec.node_name))
            f.write("#" * 180 + "\n")
            f.close()
            self.logger.info("Save the detailed pods information to %s successfully", file_path)
