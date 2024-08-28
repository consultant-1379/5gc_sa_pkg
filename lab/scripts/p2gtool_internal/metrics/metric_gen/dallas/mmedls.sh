#!/bin/sh

LTS_PM_SYS=$(lts_pm pp system | grep 'Total signaling')
RETCODE=$?

sig_kpi="Non5gcMmeDls_sig_kpi"

if [ $RETCODE -eq 0 ];then
  SIG_TOT_VAL=$(echo $LTS_PM_SYS |  awk '{if($4>0) {print $4} else {print "0.000"}}')
  echo $sig_kpi=${SIG_TOT_VAL%\%*}
else
  echo $sig_kpi="0.000"
fi
