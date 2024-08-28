#!/bin/sh

set -e

BASEDIR=$(dirname "$0")
default_ipv4cfg=$BASEDIR/bird.conf
default_ipv6cfg=$BASEDIR/bird6.conf
BIRD_CFG=$default_ipv4cfg
BIRD6_CFG=$default_ipv6cfg
BIRD_PID_FILE=/var/run/bird.pid
BIRD6_PID_FILE=/var/run/bird6.pid
BIRD_CTL_FILE=/var/run/bird.ctl
BIRD6_CTL_FILE=/var/run/bird6.ctl


function start_bird()
{
  if [ -f $BIRD_PID_FILE ];then
    echo "seems Bird is already running!"
  else
    if [ -f $BIRD_CFG ];then
      echo -n "Starting Bird ..."
      bird -c $BIRD_CFG -P $BIRD_PID_FILE
      echo "[OK]"
    fi
  fi
}

function start_bird6()
{
  if [ -f $BIRD6_PID_FILE ];then
    echo "seems Bird6 is already running!"
  else
    if [ -f $BIRD6_CFG ];then
      echo -n "Starting Bird6 ..."
      bird6 -c $BIRD6_CFG -P $BIRD6_PID_FILE
      echo "[OK]"
    fi
  fi

}


function stop_bird()
{
  # for ipv4
  if [ -f $BIRD_PID_FILE ];then
    _PID=$(cat $BIRD_PID_FILE)
    if [[ $_PID -gt 0 ]];then
      kill $_PID && echo "Stopping bird [OK]"
    else
      echo "Warning: removed empty BIRD PID FILE!"
      rm -f $BIRD_PID_FILE
      rm -f $BIRD_CTL_FILE
    fi
  else
    echo "Sorry, seems the Bird is not running!"
  fi
}

function stop_bird6()
{
  if [ -f $BIRD6_PID_FILE ];then
    _PID=$(cat $BIRD6_PID_FILE)
    if [[ $_PID -gt 0 ]];then
      kill $_PID && echo "Stopping bird6 [OK]"
    else
      echo "Warning: removed empty BIRD6 PID FILE!"
      rm -f $BIRD6_PID_FILE
      rm -f $BIRD6_CTL_FILE
    fi
  else
    echo "Sorry, seems the Bird6 is not running!"
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
            BIRD_CFG=$(echo "$1" | awk -F, '{print $1}')
            BIRD6_CFG=$(echo "$1" | awk -F, '{print $2}')
            shift
            ;;
        --start)
            start_bird && start_bird6
            break
            ;;
        --stop)
            stop_bird && stop_bird6
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
