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
stability_cli="/root/GetDuration.sh"

while True:
  try:
    ssh = pexpect.spawn("ssh -p 2222 pcc-operator@10.137.48.41",timeout=20)
    output = ssh.expect([".*password:","continue connecting \(yes/no\)\?"])
    if output == 1:
      ssh.sendline("yes")
    elif output == 0:
      ssh.sendline("Wpp_Mme_n28-1")
    output = ssh.expect(["eric-pc-sm-controller-.*#"])
    ssh.sendline(smfcli)
    ssh.expect(["eric-pc-sm-controller-.*#",pexpect.EOF])
    smf_reboot = len(list(filter(None,list(set(ssh.before.split('\r\n')))))) - 2
    os.system('echo {} {} | curl --data-binary @- http://pushgateway.ingress.n28-eccd1.sero.gic.ericsson.se/metrics/job/prometheus-pushgateway/instance/{}'.format(smf_label,smf_reboot,instance_name))   
    ssh.sendline("exit");time.sleep(1)
    ssh.close(force=True)
  except:
    print "failure once at smf"
  try:
    ssh = pexpect.spawn("ssh pcc-operator@10.137.48.35",timeout=20)
    output = ssh.expect([".*assword:","continue connecting \(yes/no\)\?"])
    if output == 1:
      ssh.sendline("yes")
    elif output == 0:
      ssh.sendline("Wpp_Mme_n28-1")
    output = ssh.expect(["eric-pc-mm-controller-0 ANCB ~ #"])
    ssh.sendline(amfcli)
    ssh.expect(["eric-pc-mm-controller-0 ANCB ~ #",pexpect.EOF])
    amf_alarm = ssh.before.split("SgsnMme=1  ")[-1].split("\r\n\r\n\r\n")[0]
    os.system('echo {} {} | curl --data-binary @- http://pushgateway.ingress.n28-eccd1.sero.gic.ericsson.se/metrics/job/prometheus-pushgateway/instance/{}'.format(amf_label,amf_alarm,instance_name))
    ssh.sendline("exit");time.sleep(1)
    ssh.close(force=True)
  except:
    print "failure once at amf"
  try:
    ssh = pexpect.spawn("ssh root@selnpctool-1096-01-001.seln.ete.ericsson.se",timeout=20)
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
      os.system('echo {} {} | curl --data-binary @- http://pushgateway.ingress.n28-eccd1.sero.gic.ericsson.se/metrics/job/prometheus-pushgateway/instance/{}'.format(m,n,instance_name))
    ssh.sendline("exit");time.sleep(1)
    ssh.close(force=True)
  except:
    print "failure once at dls"
  try:
    ssh = pexpect.spawn("ssh root@10.137.60.24",timeout=20)
    output = ssh.expect([".*assword:","continue connecting \(yes/no\)\?"])
    if output == 1:
      ssh.sendline("yes")
    elif output == 0:
      ssh.sendline("lmc_xdg")
    output = ssh.expect(["root@selnpctool-.* ~]#"])
    ssh.sendline(stability_cli)
    ssh.expect(["\[root@selnpctool-.* ~]#",pexpect.EOF])
    metric_value = ssh.before.splitlines()[1]
    os.system('echo {} {} | curl --data-binary @- http://pushgateway.ingress.n28-eccd1.sero.gic.ericsson.se/metrics/job/stability'.format(metric_name, metric_value,instance_name))
    #requests.post('http://pushgateway.ingress.n28-eccd1.sero.gic.ericsson.se/metrics/job/stability',data='%s %s\n' % (metric_name, metric_value), headers=headers)
    ssh.sendline("exit");time.sleep(1)
    ssh.close(force=True)
  except:
    print "failure once at stability"

  time.sleep(30)
