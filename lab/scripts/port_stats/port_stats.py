#!/usr/bin/python

import sys
import os
import signal
import re
import time
import copy
from pprint import pprint

OVS_CMD = "ovs-appctl dpctl/show -s netdev@ovs-netdev | sed 's/\?/0/g'"
#OVS_PMD_CMD = "ovs-appctl dpif-netdev/pmd-stats-show"
OVS_PMD_CMD = "ovs-appctl dpif-netdev/pmd-stats-show | grep -A 12 numa | grep 'proc' | cut -d'(' -f2 | cut -d')' -f1 | cut -d'/' -f2"
PMD_STATS_CLEAR_CMD = "ovs-appctl dpif-netdev/pmd-stats-clear"


TITLE = "RxKpps TxKpps RxD TxD RxGbps TxGbps"
PMD_TITLE = "PMD_Usage: CPU(Kpps)"

Red = '\033[31m'
Green = '\033[32m'
Yellow = '\033[33m'
Blue = '\033[34m'
Magenta = '\033[35m'
Cyan = '\033[36m'
HRed = '\033[41m'
HGreen = '\033[42m'
HYellow = '\033[43m'
ENDC = '\033[0m'
BOLD = '\033[1m'
UNDERLINE = '\033[4m'

def get_pmd_stats():

    raw_data =  os.popen(OVS_PMD_CMD).read().splitlines()
    pmd_stats_dict = {}
    pmd_cpu = 0
    for line in raw_data:
        if 'core_id' in line:
            m = re.search('core_id (\d+)', line)
            if m != None:
                pmd_cpu = m.group(1)
        elif 'processing cycles:' in line:
            m = re.search('\((\S+)\)', line)
            if m != None:
                pmd_stats_dict[pmd_cpu] = m.group(1)

    return pmd_stats_dict

def get_port_stats(port_list):
    
    port_monitor_list = copy.deepcopy(port_list)
    raw_data = os.popen(OVS_CMD).read().splitlines()

    port_dict = {}
    port_found = False

    for line in raw_data:
        if 'port' in line:
            m = re.match('\s+port (\d+): (\S+)', line)
            if m != None:
                port_id = m.group(1)
                port_name = m.group(2)
                if port_id in port_monitor_list:
                    port_monitor_list.remove(port_id)
                    stats_dict = {}
                    stats_dict['name'] = port_name
                    port_dict[port_id] = stats_dict
                    port_found = True
                else:
                    port_found = False
        elif port_found == True:
            if 'packets' in line:
                m = re.match('\s+(RX|TX) packets:(\d+) errors:(\d+) dropped:(\d+)', line) 
                if m != None:
                    if m.group(1) == 'RX':
                        port_dict[port_id]['rx_packets'] = int(m.group(2))
                        port_dict[port_id]['rx_errors'] = int(m.group(3)) 
                        port_dict[port_id]['rx_dropped'] = int(m.group(4)) 
                    else:
                        port_dict[port_id]['tx_packets'] = int(m.group(2)) 
                        port_dict[port_id]['tx_errors'] = int(m.group(3)) 
                        port_dict[port_id]['tx_dropped'] = int(m.group(4)) 
            elif 'bytes' in line:
                m = re.match('\s+RX bytes:(\d+).*TX bytes:(\d+)', line)
                if m != None:
                    port_dict[port_id]['rx_bytes'] = int(m.group(1)) 
                    port_dict[port_id]['tx_bytes'] = int(m.group(2)) 
    if port_monitor_list:
        print "Error: port {0} not found or duplicate port parameters!".format(port_monitor_list)
        usage()
  
    return port_dict 


def get_delta_stats(stats_crnt, stats_prvs):

    delta_stats = {}
    for stat in stats_prvs.keys():
        if stat == 'name':
            delta_stats[stat] = stats_prvs[stat]
        else:
            delta_stats[stat] = int(stats_crnt[stat]) - int(stats_prvs[stat])

    return delta_stats

def print_port_stats(port_list, log_file, start_time, file_duration, interval=1, title_print=5):

    port_stats_prvs = get_port_stats(port_list)
    
    row_count = 0
  
    
    while 1:

        current_time = time.time()
        duration = current_time - start_time
        if duration > file_duration:
            break
    
        if row_count % title_print == 0:
            print >> log_file, BOLD + Yellow + 'TIME      ' + '|'  + (TITLE + '| ') * len(port_list) + PMD_TITLE + ENDC

        os.popen(PMD_STATS_CLEAR_CMD)

        time.sleep(interval)

        print >> log_file, "{0:10}".format(time.strftime('%m%d%H%M%S')),

        port_stats_crnt = get_port_stats(port_list)
        pmd_stats = os.popen(OVS_PMD_CMD).read().splitlines()
    
        delta_port_stats = {}
    
        for port_id in port_stats_crnt.keys():
            delta_port_stats[port_id] = get_delta_stats(port_stats_crnt[port_id], port_stats_prvs[port_id])
                
        port_stats_prvs = port_stats_crnt
    
        for port_id in port_list:
            print >> log_file, "{0}{1:<7.1f}{2:<7.1f}{3}{4:<4d}{5:<4d}{6}{7:<7.3f}{8:<6.3f}{9}|".format(\
                  Green, \
                  delta_port_stats[port_id]['rx_packets'] / 1000.0 / float(interval), \
                  delta_port_stats[port_id]['tx_packets'] / 1000.0 / float(interval), \
                  Red, \
                  delta_port_stats[port_id]['rx_dropped'], \
                  delta_port_stats[port_id]['tx_dropped'], \
                  Blue, \
                  delta_port_stats[port_id]['rx_bytes'] * 8 / 1024.0 / 1024.0 / 1024.0 / float(interval), \
                  delta_port_stats[port_id]['tx_bytes'] * 8 / 1024.0 / 1024.0 / 1024.0 / float(interval), \
                  ENDC), 

        for stats in pmd_stats:
            if stats.isdigit():
                proc_mpps = int(stats) / 1000.0 / float(interval)
                print >> log_file, "({0:.0f})".format(proc_mpps),
            else:
                print >> log_file, stats,
    
        row_count = row_count + 1
        print >> log_file
        #sys.stdout.flush()
        f.flush()

def usage():
    print """
    Script 'port_stats.py' is used to monitor the OVS statitics when running load test.
    It should be run on compute host with root priviledge.
    Provide port(digit) list to be monitored as parameter.
    e.g. port_stats.py 1 2 3 4
    By default, the script samples the statistics every 5 seconds. 
    Yacht can be used to get the port number on CEE.
    get_port.py can be used to get the port number on RHOSP.
    """
    sys.exit(1)


if __name__ == "__main__":


    # kill the exsiting running processes to avoid duplicate running
    pid = os.getpid()
    existing_processes = os.popen("ps -ef | grep port_stats | grep -v grep | grep python | grep -v {0}".format(pid)).read().splitlines()
    for process in existing_processes:
        existing_pid = int(process.split()[1])
        os.kill(existing_pid, signal.SIGKILL)

    data_interval = 30
    title_interval = 30
    file_duration = 86400

    if len(sys.argv) < 2:
        usage()

    port_list = sys.argv[1:]

    for port in port_list:
        if port.isdigit() == False:
            print "Error: please input digit port number as parameter."
            usage()

    script_path = os.path.dirname(os.path.abspath(__file__))
    hostname_short = os.uname()[1].split(".")[0]

    while 1:
        start_time = time.time()
        log_filename = script_path + "/" + hostname_short + "-port_stats-" + time.strftime('%m%d%H%M%S') + ".log"
        with open(log_filename, 'w') as f:
            print >> f, "port_list: {0}".format(port_list)
            print_port_stats(port_list, f, start_time, file_duration, data_interval, title_interval)
