#!/bin/bash

# 2015-09-23: ervmapa
# adding variable -r for resetting diff values. Example  -r "17:43:00"

################################################################################
# Usage information
################################################################################
usage () {

  echo
  echo "This script calculates and displays payload loss. Either the default Dallas"
  echo "log file /var/log/dallas_pm.log is used for input or any saved file with same"
  echo "data format can be used. By default the accumulated payload loss is displayed"
  echo "with the calculated ppm value (packets per million). With the '-d' option a"
  echo "delta value (incremental) can also be displayed. A '-v' option, verbose, is"
  echo "available to get more detailed information when Dallas is configured for test"
  echo "of S-GW."
  echo
  echo
  echo "Usage: `basename $0` [-h] [-d] [-v] [-f <pm_file>]"
  echo
  echo "  -d   Display delta values (increase since previous value)"
  echo "  -v   Verbose output (for S-GW config)"
  echo "  -f   Use selected file as input (default /var/log/dallas_pm.log)"
  echo "  -h   Show usage information"
  echo
  exit 0
}

################################################################################
# lts_pmshow for combined node under test
################################################################################
pmshow_cgw () {

gidl_x=0
giul_x=0
gndl_x=0
gnul_x=0
dlbyte_x=0
ulbyte_x=0
sigdiff_x=0




#/lab/epg_st_utils/testtools/dallas/rhel6.x86_64/R10A87/mnsserv/bin/
lts_pmshow ${file} -c 'LTT Payload - Gn/Iuu UL packets - Value;LTT Payload - Gi UL packets - Value;LTT Payload - Gi DL packets - Value;LTT Payload - Gn/Iuu DL packets - Value;LTT Payload - Gi DL packets - Rate;LTT Payload - Gi UL bytes - Value;LTT Payload - Gn/Iuu DL bytes - Value;LTT Payload - Gn/Iuu UL packets - Rate;Total signaling KPI - Successful;Total signaling KPI - Failed;MME - Active UEs - Value;S4-SGSN - Active UEs - Value;SGW - Active UEs - Value;SGSN - Activated MSs - Value;' | awk -v showdelta=${delta} -v showverbose=${verbose} -v offset_ul=0 -v offset_dl=0 -v ref_time=${ref_time} '{
    date=$1
    if (date != "Time")
    {
      if (date ~ /^20[0-9][0-9]-/)
      {
        time=$2
        gnul=$3
        giul=$4
        gidl=$5
        gndl=$6
        dlrate=$7
        ulbyte=$8
        dlbyte=$9
        ulrate=$10
        sigsuc=$11
        sigfai=$12
        mme_ue=$13
        s4sgsn_ue=$14
        sgw_ue=$15
        sgsn_ue=$16
        uldiff=gnul-giul-offset_ul
        dldiff=gidl-gndl-offset_dl

    if ( time == ref_time)
    {
#    print "* Ref *"
#    offset_ul = uldiff
#    offset_dl = dldiff
#    uldiff=0
#    dldiff=0
#    gidl_x=gidl
#    giul_x=giul
#    gndl_x=gndl
#    gnul_x=gnul
    }
#    gidl=gidl-gidl_x
#    giul=giul-giul_x
#    gndl=gndl-gndl_x
#    gnul=gnul-gnul_x

        uldelta=uldiff-prevuldiff
        dldelta=dldiff-prevdldiff
        prevuldiff=uldiff
        prevdldiff=dldiff
        sigsucdiff=sigsuc-prevsigsuc
        sigfaidiff=sigfai-prevsigfai
        prevsigsuc=sigsuc
        prevsigfai=sigfai
        dlbyte_rate=(dlbyte-dlbyte_x)*8/(60*1000000000+0.001)
        ulbyte_rate=(ulbyte-ulbyte_x)*8/(60*1000000000+0.001)
        dlbyte_x=dlbyte
        ulbyte_x=ulbyte
#(1-sigfai/((sigsuc+0.001))*100)
        if (showdelta ~ /true/)
         {
          format="%-10s  %-8s  %11i  %11i  %11i  %11i  %9.1f  %8.1f  %8i  %6.1f  %6.1f  %10.3f %11.3f %8i\n"
          printf format, date, time, uldiff, uldelta,  dldiff, dldelta, (dldelta+uldelta)*1000000/((ulrate+dlrate)*60+0.001), (dldiff+uldiff)*1000000/(gidl+gnul+0.01),(ulrate+dlrate)/1000,ulbyte_rate,dlbyte_rate,(1-sigfaidiff/(sigsucdiff+0.0000001))*100,(1-sigfai/((sigsuc+0.00000001)))*100,(mme_ue+s4sgsn_ue+sgw_ue+sgsn_ue)
        } else {
          format="%-10s  %-8s  %10i  %13.1f  %10i  %13.1f\n"
          printf format, date, time, uldiff, 1000000*(uldiff)/(gnul+0.001), dldiff, 1000000*(dldiff)/(gidl+0.001)
        }
      }
    }
  }'

}

################################################################################
# MAIN
################################################################################

# Parse command line
file=""
delta="true"
verbose="false"
loop="true"
ref_time="false"
interval=60

#total signaling
#lts_pm pp system | grep 'Total signaling' | awk '{print $3,$4,$5,$6}'
#pmshow
total_lead_time=$(pmshow_cgw | awk '{if($14>0) print $0}' | wc -l)
lastmins=${1:-1}

metric_name=("Non5gcDls_ppm_delta" "Non5gcDls_pps" "Non5gcDls_payload_tot" "Non5gcDls_sig_delta" "Non5gcDls_ue_tot" "Non5gcDls_st_leadtime")
metric_value=($(pmshow_cgw | tail -$lastmins | awk -v arg1=$arg1 '{print $7,$9,$10+$11,$12,$14,"'$total_lead_time'"}'))

i=0
for m in ${metric_name[@]}
do
    echo $m=${metric_value[$i]:-0}
    let i++
done

