#!/bin/bash
if [ "x$*" == "x" ]; then echo "Usage: ./genkey_mp.sh [start] [vol_each] [num]"; exit 1; fi
if [ "x$1" == "x" ]; then echo "Missing parameter: start"; exit 1; fi
if [ "x$2" == "x" ]; then echo "Missing parameter: vol_each"; exit 1; fi
if [ "x$3" == "x" ]; then echo "Missing parameter: num"; exit 1; fi

start=$1
vol_each=$2
num=$3

i=0
while [ "$i" -lt "$num" ]
do
        ./genkey.sh $start $vol_each > "data$i.txt" &
        start=$[$start+$vol_each]
        i=$[$i+1]
done
