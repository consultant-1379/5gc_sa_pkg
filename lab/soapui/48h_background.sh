#!/bin/bash

if [ "x$*" == "x" ]; then echo "Usage: ./48h_background.sh [logfile]"; exit 1; fi

LOGFILE=$1

nohup ./48h.sh $LOGFILE 2>&1 > /dev/null &

exit 0

