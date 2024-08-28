import subprocess
import os
import time
import re
import threading

FAIL_RESULT = 1
SUC_RESULT = 0


# the function is not just for getting the log path ,
# but also to avoid the full buffer issue
def get_script_log_path(namespace, processes_state: dict, cnf_namespaces: list):
    sub_proc = processes_state[namespace][0]
    output = None
    while output != '':
        if len(cnf_namespaces) == 1 and len(str(output)) > 1:
            print(output)
        output = sub_proc.stdout.readline()
        searchObj = re.search(r'.* Please check the logs in (.*) for more info.*',
                              output, re.M | re.I)
        if searchObj is not None:
            processes_state[namespace][2] = searchObj.group(1)


class HealthCheck(object):

    def __init__(self, cnf_namespaces=None, logger=None, cluster=None, log_path=None):
        self.cnf_namespaces = cnf_namespaces
        self.logger = logger
        self.log_path = log_path
        self.cluster = cluster
        os.system("rm -f ~/.sputils/k8s/fivegc-cnf-healthcheck/fivegc-cnf-healthcheck.sh")


    def run_health_check_script(self):
        processes_state = {}
        for ns in self.cnf_namespaces:
            self.logger.info("Start healthcheck for %s", ns)
            sub_pid = subprocess.Popen("/lab/pccc_utils/scripts/sputils fivegc-cnf-healthcheck " + ns,
                                       shell=True, text=True, encoding="utf-8", stdout=subprocess.PIPE)
            processes_state[ns] = [sub_pid, -1, -1]
            time.sleep(1)
            th_read_buf = threading.Thread(target=get_script_log_path, args=(ns, processes_state, self.cnf_namespaces))
            th_read_buf.start()
            time.sleep(30)

        self.poll(processes_state)

    def poll(self, processes_state):
        for i in range(1, 50):
            all_sub_proc_ongoing = False
            for key in processes_state.keys():
                sub_pid = processes_state[key][0]
                processes_state[key][1] = sub_pid.poll()
                self.logger.info("Health check is ongoing, pid:%s, the return code of %s: %s", sub_pid.pid, key,
                                 processes_state[key][1])
                if sub_pid.poll() is None:
                    all_sub_proc_ongoing = True
            if all_sub_proc_ongoing:
                time.sleep(10)
            else:
                self.logger.info("Health check for %s is finished.", self.cnf_namespaces)
                for key, proc in processes_state.items():
                    hc_file_parent_path = str.replace(os.path.basename(proc[2]), "--", "-" + self.cluster + "-")
                    os.system("mv " + proc[2] + " " + self.log_path + os.path.sep + hc_file_parent_path)
                    hc_files_dir_name = self.log_path + os.path.sep + hc_file_parent_path + os.path.sep
                    if proc[1] == FAIL_RESULT:
                        self.logger.error("The %s is NOT in Healthy State, Please check the logs in %s ",
                                          key, hc_files_dir_name)
                    elif proc[1] == SUC_RESULT:
                        self.logger.info("The %s is in Healthy State, Please check the logs in %s ",
                                         key, hc_files_dir_name)
                    else:
                        self.logger.error("Unexpected health check result:%s", proc[1])
                break
