#!/bin/bash

if [ "x$*" == "x" ]; then echo "Usage: ./genkey_err.sh [path_to_errordata]"; exit 1; fi
if [ "x$1" == "x" ]; then echo "Missing parameter: path_to_errordata"; exit 1; fi

errors=$(cat $1)

A4Key="0123456789abcdef0123456789abcdef"

#echo "IMSI,MSISDN,KEY"
for error in $errors
do
        IMSI=$((240810000000000 + 10#$error))
        MSISDN=$((491720000000000 + 10#$error))
        dKi=`echo ${IMSI} | gawk '{ j=length($IMSI); printf("%s%s",substr($IMSI,j-7),$IMSI); for (i = j; i < 16 ; i++) printf ("0"); printf ("12345678\n") }'`
        cryKi=`echo ${dKi} | xxd -r -ps | openssl enc -aes-128-ecb -nosalt -nopad -K $A4Key -iv $A4Key 2>/dev/null | xxd -ps`
        echo "$IMSI;$MSISDN;$cryKi"
done
