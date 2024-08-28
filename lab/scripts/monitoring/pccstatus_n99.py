#!/usr/bin/env python
import time
import pexpect
import sys
import os

smfcli="epg node st | include start-time"
amfcli="gsh show_measurement_type_report -pgi SGSN-MME_ISP_ConnectionRestarts -mti gsnAutomaticConnectionRestarts"
dlscli="/root/oncepmshow_payload.sh | awk 'END{print $0}' | awk '{print $0}' | awk '{print $4,$6+$7,$12,$15}'"
instance_name='pccalarm'
amf_label="AMF_reboot_count"
smf_label="SMF_reboot_count"
dls_label=["Dallas_Sig_KPI","Dallas_TP","Dallas_PPM","Dallas_sig_fail"]
headers = {'X-Requested-With': 'Python requests', 'Content-type': 'text/xml'}
metric_name="stability_lead_time"
stability_cli="/root/cost_cal.sh"
ns = ["pcc","pcg","ccsm","ccdm","ccrc"]
alarmpodcli  = "kubectl get po -n {}  | awk \'/^eric-fh-alarm-handler/ {{print $1}}\' | head -1"

while True:
  try:
    ssh = pexpect.spawn("ssh root@10.9.80.162",timeout=20)
    output = ssh.expect([".*assword:","continue connecting \(yes/no\)\?"])
    if output == 1:
      ssh.sendline("yes")
    elif output == 0:    
      ssh.sendline("lmc_xdg")
    output = ssh.expect(["root@selnpctool-.* ~]#"])
    ssh.sendline(dlscli)
    ssh.expect(["root@selnpctool-.* ~]#",pexpect.EOF])
    dls_tmp = ssh.before.split('\r\n')[-2].split()
    for m,n in zip(dls_label,dls_tmp):
      os.system('echo {} {} | curl --data-binary @- http://pushgateway.ingress.n99-eccd1.sero.gic.ericsson.se/metrics/job/prometheus-pushgateway/instance/{}'.format(m,n,instance_name))
    ssh.sendline("exit");time.sleep(1)
    ssh.close(force=True)
  except:
    print "failure once at dls"
  try:
    ssh = pexpect.spawn("ssh root@10.9.80.162",timeout=20)
    ssh.expect(["selnpctool-.* ~]#"])
    ssh.sendline(stability_cli)
    ssh.expect(["\[root@selnpctool-.* ~]#",pexpect.EOF])
    metric_value = ssh.before.splitlines()[1]
    os.system('echo {} {} | curl --data-binary @- http://pushgateway.ingress.n99-eccd1.sero.gic.ericsson.se/metrics/job/stability'.format(metric_name, metric_value))
    #requests.post('http://pushgateway.ingress.n28-eccd1.sero.gic.ericsson.se/metrics/job/stability',data='%s %s\n' % (metric_name, metric_value), headers=headers)
    ssh.sendline("exit");time.sleep(1)
    ssh.close(force=True)
  except:
    print "failure once at stability"


  time.sleep(30)
