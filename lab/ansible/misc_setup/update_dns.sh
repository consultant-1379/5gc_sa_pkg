#!/usr/bin/env bash

set -e

# Author: Wallance Hou
# Date: 2023-08-22
# Description: configure DNS on ubuntu misc server


module ()
{
    {
        eval `/app/modules/0/bin/modulecmd bash "$@"`
    } 2>&1
}


usage()
{
  echo -e "Usage: $0 <POD_NAME, e.g: n280>"
}

main()
{
  # check if pod name is given
  supported_pod=(n280 n99)
  if [ $# -ge 1 ];then
    POD=$1
    if [[ ! " ${supported_pod[@]} " =~ " $POD " ]];then
      echo Error: the given pod "'$POD'" is not supported
      exit 1
    fi
    # load ansible env
    # Add ansible 2.12.1 bin PATH as ansible version is older on Terminal Server.
    export PATH=/lab/pccc_utils/scripts/csdp_python3_venv/bin:$PATH
    module add sshpass

    basedir=$(dirname $(readlink -e $0))
    tgpp_dns_config_dir="$basedir/../../misc/$POD/DNS/"
    vault_pass='Misc$ecr1t'
    sshpass -p "$vault_pass" ansible-playbook \
      -i $basedir/config/inventory/misc.yaml $basedir/playbooks/configure_dns.yml \
      -e "target_pod=$POD tgpp_dns_config_dir=$tgpp_dns_config_dir" \
      --ask-vault-pass
  else
    usage
  fi
}

main $@
