#!/bin/bash

if [ "x$*" == "x" ]; then echo "Usage: ./genkey.sh [start] [volume]"; exit 1; fi
if [ "x$1" == "x" ]; then echo "Missing parameter: start"; exit 1; fi
if [ "x$2" == "x" ]; then echo "Missing parameter: volume"; exit 1; fi

START_IMSI=$(expr 240810000000000 + $1)
START_MSISDN=$(expr 491720000000000 + $1)
VOLUME=$2

A4Key="0123456789abcdef0123456789abcdef"

#echo "IMSI,MSISDN,KEY"
for ((count = 0; count < $VOLUME; count++))
do
        IMSI=$(expr $START_IMSI + $count)
        MSISDN=$(expr $START_MSISDN + $count)
        dKi=`echo ${IMSI} | gawk '{ j=length($IMSI); printf("%s%s",substr($IMSI,j-7),$IMSI); for (i = j; i < 16 ; i++) printf ("0"); printf ("12345678\n") }'`
        cryKi=`echo ${dKi} | xxd -r -ps | openssl enc -aes-128-ecb -nosalt -nopad -K $A4Key -iv $A4Key 2>/dev/null | xxd -ps`
        echo "$IMSI;$MSISDN;$cryKi"
done
