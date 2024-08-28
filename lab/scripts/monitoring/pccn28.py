#!/usr/bin/env python
import time
import pexpect
import sys
import os

cli=["epg pgw statistics of brief",\
"epg node status",\
"epg pgw sbi client-status",\
"epg pgw sbi smf-services status",\
"epg node fa ac",\
'epg node internal-debug execute cmd-string "show istats sacc"',\
'epg node internal-debug execute cmd-string "show istats udm"',\
'epg node internal-debug execute cmd-string "show istats pgw.sessionengine*"',\
'epg node internal-debug execute cmd-string "show istats pdu"',\
'epg node internal-debug execute cmd-string "show istats pdp" | inc DeleteReason',\
'epg node internal-debug execute cmd-string "show istats pgw.ppb.sx"',\
'epg node internal-debug execute cmd-string "show istats pgw.destroy"',\
'']

amfcli=['eci list',\
'gsh list_events',\
'gsh show_measurement_type_report -pgi SGSN-MME_ISP_ConnectionRestarts -mti gsnAutomaticConnectionRestarts',\
'']


dallascli=["lts_pm p nr",\
"~/oncepmshow_payload.sh",\
""]

n = 0

while True:
  try:
    fout = open ("smf.log", "ab")
    ssh = pexpect.spawn("/lab/pccc_utils/scripts/l n28-smf1",timeout=20,logfile=fout)
    output = ssh.expect(["eric-pc-sm-controller-.*#"])
    fout.writelines('\n%%%%%%%'+time.ctime()+'%%%%%%%%\n')
    for i in cli:
      ssh.sendline(i)
      ssh.expect(["eric-pc-sm-controller-.*#",pexpect.EOF])
    ssh.sendline("exit")
    time.sleep(1)
    fout.writelines("\n%%%%%%finished%%%%%%%\n")
    fout.close
    ssh.close(force=True)
  except:
    print "failure once at smf"
  try:
    fout = open ("amf.log", "ab")
    ssh = pexpect.spawn("/lab/pccc_utils/scripts/l n28-amf1",timeout=20,logfile=fout)
    output = ssh.expect(["eric-pc-mm-controller-0 ANCB ~ #"])
    fout.writelines('\n%%%%%%%'+time.ctime()+'%%%%%%%%\n')
    for i in amfcli:
      ssh.sendline(i)
      ssh.expect(["eric-pc-mm-controller-0 ANCB ~ #",pexpect.EOF])
    ssh.sendline("exit")
    time.sleep(1)
    fout.close
    ssh.close(force=True)
  except:
    print "failure once at amf"

###dallas
  try:
    fout = open ("dallas.log", "ab")
    ssh = pexpect.spawn("/lab/pccc_utils/scripts/l n28-dls001",timeout=10,logfile=fout)
    output = ssh.expect([".*~]#"])
    fout.writelines("\r%%%%%%%%%%%%%%%%%%\r")
    fout.writelines(time.ctime())
    for i in dallascli:
      ssh.sendline(i)
      time.sleep(5)
      ssh.expect([".*~]#",pexpect.EOF])
    fout.writelines("%%%%%%%%%%%%%%%%%%")
    ssh.sendline("exit")
    fout.close
    ssh.close(force=True)
  except:
    print "failure once at dallas"
  break
  time.sleep(30)
    #os.system("ps -eaf | grep etbbccg | grep '10.137.48' | grep ssh | awk '{print $2}' | xargs -i{} kill {}")
