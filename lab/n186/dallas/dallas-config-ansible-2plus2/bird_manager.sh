#!/bin/sh

set -e

BASEDIR=$(dirname "$0")
default_cfg=$BASEDIR/bird.conf
BIRD_CFG=$default_cfg
BIRD_PID_FILE=/var/run/bird.pid


function start_bird()
{
  if [ -f $BIRD_PID_FILE ];then
    echo "seems Bird is already running!"
  else
    echo -n "Starting Bird ..."
    bird -c $BIRD_CFG -P $BIRD_PID_FILE
    echo "[OK]"
  fi
}


function stop_bird()
{
  if [ -f $BIRD_PID_FILE ];then
    _PID=$(cat $BIRD_PID_FILE)
    if [[ $_PID -gt 0 ]];then
      kill $_PID && echo "Stopping bird [OK]"
    else
      echo "Warning: removed empty BIRD PID FILE!"
      rm -f $BIRD_PID_FILE
    fi
  else
    echo "Sorry, seems the Bird is not running!"
  fi
}

function ret_usage()
{
  echo $0 '<[--start | --stop ]>'
  exit 0
}

function main()
{
  if [ $# -ge 1 ] ; then
    while [ 1 ] ; do
      case $1 in
        -c|--config)
            shift
            BIRD_CFG=$1
            shift
            ;;
        --start)
            start_bird
            break
            ;;
        --stop)
            stop_bird
            break
            ;;
        --)
            shift; break;
            ;;
        -h|--help)
            ret_usage
            exit 0
            ;;
        -*)
            echo "unknown option: $1" >&2
            exit 7
            ;;
        *)
            ret_usage
            ;;
        esac
    done
  
  else
    ret_usage
    exit 8
  fi
}


main $@
