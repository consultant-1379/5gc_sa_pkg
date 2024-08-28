#!/bin/bash

logfile=$(hostname)_$(date "+%Y%m%d%H%M%S").log
while true
do
  echo $(date) >> $logfile
  echo '' >> $logfile
  cat /proc/net/dev | column -t >> $logfile
  echo '' >> $logfile
  sleep 30
done

