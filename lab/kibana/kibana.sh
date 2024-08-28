#!/bin/bash

# Author: Wallance Hou
# Date: 2021-10-25
# Desc: Kibana Appliance POD LCM for ALL CNFs

function help()
{
  PROG=kibana
  echo -e "Usage: $PROG <[gen_config|info|start|stop|delete]> <[CNF1 CNF2 ...]>"
  echo
  echo -e "Supported CNFs: pcc, ccrc, ccsm, ccdm"
}

function gen_config()
{
  pod=$(hostname | awk -F\- '{print $1}')
  domain=sero.gic.ericsson.se
  if [[ $pod =~ ^pod[0-9]+$ ]];then
    domain=seln.ete.ericsson.se
  elif [[ $1 =~ ^pod[0-9]+$ ]];then
    pod=$1
    domain=seln.ete.ericsson.se
    shift
  fi

  for item in $@
  do
    cnf=$(echo $item | awk -F: '{print $1}')
    cluster=$(echo $item | awk -F: '{print $2}')
    cluster=${cluster:-eccd1}
    config_dir="$(dirname $(readlink -e $0))/$cnf"
    proto=http
    svc_name=eric-data-search-engine
    use_ssl_cnfs=(pcg eda sc)
    if [[ " ${use_ssl_cnfs[@]} " =~ " $cnf " ]];then
      proto=https
      svc_name=eric-data-search-engine-tls
    fi

    [ ! -d $config_dir ] && mkdir $config_dir
    kibana_conf=$config_dir/kibana.yml

    url="${proto}://${cnf}-${svc_name}.ingress.${pod}-${cluster}.$domain"
    cat << EOF > $kibana_conf
server.name: kibana
server.host: "0.0.0.0"
elasticsearch.hosts: ["$url"]
EOF
  [ $? -eq 0 ] && echo $cnf kibana config file $kibana_conf is generated.
  done
}

function get_container_status()
{
  cnf=$1
  docker ps -a | grep "[[:space:]]kibana-$cnf" | awk '{print $7}'
}

function kibana_manager()
{
  local act cnfs
  cnfs=()
  act=$1
  shift

  for i in $@
  do
    cnfs+=("kibana-$i")
  done
  docker $act ${cnfs[@]}
}

function run_kibana()
{
  local cnf port pod
  cnf=$1
  port=$2
  if grep -q ".pod56-" /opt/user_docker/kibana/${cnf}/kibana.yml;then
    docker run -d --restart=always --name kibana-${cnf} -p ${port}:5601 -v /opt/user_docker/kibana/${cnf}/kibana.yml:/usr/share/kibana/config/kibana.yml docker.elastic.co/kibana/kibana-oss:7.8.1
  else
    docker run -d --restart=always --log-driver json-file --log-opt max-size=100m --log-opt max-file=2 --name kibana-${cnf} -p ${port}:5601 -v /opt/user_docker/kibana/${cnf}/kibana.yml:/usr/share/kibana/config/kibana.yml docker.elastic.co/kibana/kibana-oss:7.8.1
  fi
}

function reset_kibana()
{
  local cnf
  ALL_CNFs=(pcc:9200 pcg:9201 ccrc:9202 ccsm:9203 ccdm:9204 eda:9205 sc:9206)
  input_valid_cnfs=()
  act=$1
  shift

  if [ $1 == ALL ];then
    input_valid_cnfs=(${ALL_CNFs[@]})
  else
    for cnf in ${ALL_CNFs[@]}
    do
      if [[ " $@ " =~ [[:space:]]$(echo $cnf | awk -F: '{print $1}')[[:space:]] ]];then
        input_valid_cnfs+=($cnf)
      fi
    done
  fi

  for item in ${input_valid_cnfs[@]}
  do
    cnf=$(echo $item | awk -F: '{print $1}')
    port=$(echo $item | awk -F: '{print $2}')
    status=$(get_container_status $cnf)
    if [[ -z $status ]];then
      run_kibana $cnf $port
    else
      kibana_manager $act $cnf
    fi
  done
}

function main()
{
  if [ $# -ge 1 ];then
    case $1 in
        info) 
	    shift
            docker ps -a | grep kibana
	    ;;
      gen_config) 
	    shift
	    gen_config $@
	    ;;
      start) 
	    shift
	    reset_kibana start $@
	    ;;
       stop)
	    shift
	    reset_kibana stop $@
	    ;;
     delete)
	    shift
	    reset_kibana stop $@
	    reset_kibana rm $@ ;;
          *) help ;;
    esac
  else
    help
  fi
}

main $@
