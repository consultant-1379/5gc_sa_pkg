#!/bin/bash

if [ "x$*" == "x" ]; then echo "Usage: ./48h.sh [logfile]"; exit 1; fi

LOGFILE=$1

log_to_file() {
	(date;echo $1) >> $LOGFILE
}

log_to_file '48h start'

log_to_file 'starting 1st 12-hour iteration'

/home/tsuser/SoapUI-5.5.0/bin/loadtestrunner.sh /home/tsuser/ehuafna//MBB-5G-soapui-project.xml -s 5G-REST-batch -c stab-back-traffic -l simple -r  -f /home/tsuser/ehuafna/log/stab_48/1

log_to_file 'ending 1st 12-hour iteration'

sleep 20

log_to_file 'starting 2nd 12-hour iteration'

/home/tsuser/SoapUI-5.5.0/bin/loadtestrunner.sh /home/tsuser/ehuafna//MBB-5G-soapui-project.xml -s 5G-REST-batch -c stab-back-traffic -l simple -r  -f /home/tsuser/ehuafna/log/stab_48/2

log_to_file 'ending 2nd 12-hour iteration'

sleep 20

log_to_file 'starting 3rd 12-hour iteration'

#/home/tsuser/SoapUI-5.5.0/bin/loadtestrunner.sh /home/tsuser/ehuafna//MBB-5G-soapui-project.xml -s 5G-REST-batch -c stab-back-traffic -l simple -r  -f /home/tsuser/ehuafna/log/stab_48/3

log_to_file 'ending 3rd 12-hour iteration'

sleep 20

log_to_file 'starting 4th 12-hour iteration'

#/home/tsuser/SoapUI-5.5.0/bin/loadtestrunner.sh /home/tsuser/ehuafna//MBB-5G-soapui-project.xml -s 5G-REST-batch -c stab-back-traffic -l simple -r  -f /home/tsuser/ehuafna/log/stab_48/4

log_to_file 'ending 4th 12-hour iteration'

sleep 20

log_to_file '48h end'

exit 0
