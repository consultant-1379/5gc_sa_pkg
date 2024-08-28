#!/bin/bash


# background color

function module ()
{
    {
        eval `/app/modules/0/bin/modulecmd bash "$@"`
    } 2>&1
}

function debug()
{
    echo -e "\033[37m$1\033[0m"
}
function log_info()
{
    echo -e "\033[32m$1\033[0m"
}
function warn()
{
    echo -e "\033[33m$1\033[0m"
}
function log_error()
{
    echo -e "\033[31m$1\033[0m"
}

function usage() {
  echo;
  log_info 'Description: Run it on any server on which can reach CCDM OAM IP/FQDN.'
  log_info 'usage: ./ccdm-prov-func-Init-Conf.sh <OAM_FQDN_AND_PORT>'
  log_info 'usage:Example: ./ccdm-prov-func-Init-Conf.sh https://oam.ccdm.n84-eccd1.sero.gic.ericsson.se:443'
  echo;
}

#the running result of the script 0:failed; 1:success
module add jq/1.5
module list
RES_FLAG=1
if [ $# -ne 1  ]
then
  log_error "The param number is wrong."
  usage
  exit 1
else
  if [[ "$1" == "-h" ]]
  then
    usage
    exit 1
  fi
  # Check if the 'jq' app is there 
  jq_ready=$(jq -n null)
  #echo $jq_ready
  if [[ "${jq_ready}" == "null" ]]
  then
    log_info "### You are running $0 $1 ."
  else
    log_error "### the jq app is not ready. please run 'module add jq/1.5'beore this script, Exiting..."
    usage
    exit 1
  fi
fi

#OAM_FQDN_AND_PORT='https://oam.ccdm.n84-eccd1.sero.gic.ericsson.se:443'
OAM_FQDN_AND_PORT=$1
password=Password!1234
users_list=(mapi proclog)

log_info "### Onboarding of a Service Account" | tee ccdm-prov-func-Init-Conf.log
create_svc_acc_res=$(curl -k -X POST -H 'Content-Type: application/json' -d "{\"users\":[],\"service_account\":[{\"user_name\":\"superuser@ericsson.com\",\"password\":\"${password}\"}],\"clients\":[{\"client_name\":\"aaa-client\"}]}" ${OAM_FQDN_AND_PORT}/oauth/v1/onboard)

log_info "### Onboarding of a Service Account Result $create_svc_acc_res" | tee -a ccdm-prov-func-Init-Conf.log
create_svc_acc_res=$(echo ${create_svc_acc_res} | jq .)
#create_svc_acc_res=$(cat /home/edekkon/core_id.json )
client_id=$(echo $create_svc_acc_res |jq '.clients[0].client_id' |sed 's/\"//g')
client_secret=$(echo $create_svc_acc_res |jq '.clients[0].client_secret' |sed 's/\"//g')

#client_id="8024b370-48ed-11eb-a749-8b5f4842b012"
#client_secret="59280303-560c-41b5-ae54-136fdfd2d69f"


log_info "client_id:${client_id} client_secret:${client_secret}"  | tee -a ccdm-prov-func-Init-Conf.log
echo $OAM_FQDN_AND_PORT $client_id $client_secret
log_info "### Retrieve Authorization Access Token."  | tee -a ccdm-prov-func-Init-Conf.log

export access_token=$(curl -k -X POST -H "Content-Type: application/x-www-form-urlencoded" --data "client_id=${client_id}&client_secret=${client_secret}&grant_type=password&username=superuser@ericsson.com&password=${password}&scope=openid profile scopes.ericsson.com/activation/oauth.authn.user.read scopes.ericsson.com/activation/oauth.authn.user.write scopes.ericsson.com/activation/oauth.core.user.read scopes.ericsson.com/activation/oauth.core.user.write scopes.ericsson.com/activation/oauth.core.client.read scopes.ericsson.com/activation/oauth.core.client.write scopes.ericsson.com/activation/roles.read scopes.ericsson.com/activation/roles.write" ${OAM_FQDN_AND_PORT}/oauth/v1/token | jq '.access_token' |sed 's/\"//g')

log_info "### access_token:${access_token}"  | tee -a ccdm-prov-func-Init-Conf.log

for ((i=0;i< ${#users_list[@]};i=i+1))
do
  export user_name=${users_list[$i]}
  #echo $user_name
  if [[ $(echo ${user_name} |grep 'mapi') != "" ]]
  then
    export role="MAPI Provisioning"
  elif [[ $(echo ${user_name} |grep 'proclog') != "" ]]
  then
    export role="Processing log manager"
  fi

  log_info "### POST Authn User: ${user_name}" | tee -a ccdm-prov-func-Init-Conf.log
  user_res=$(curl -k -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer ${access_token}" -d "{\"user_info\":{\"given_name\":\"${user_name}\",\"family_name\":\"Ericsson\",
\"account_type\":\"service_account\"},\"email\":\"${user_name}@ericsson.com\"}" ${OAM_FQDN_AND_PORT}/oauth/v1/authn/users/profile | jq .)

  debug $user_res | tee -a ccdm-prov-func-Init-Conf.log
  user_pw=`echo $user_res | jq '.password'`
  if [[ "${user_pw}" != "" ]]
  then
   log_info "### POST Authn User: ${user_name} successful."  | tee -a ccdm-prov-func-Init-Conf.log
  else
   log_error "POST Authn User: ${user_name} failed! EXITING...."  | tee -a ccdm-prov-func-Init-Conf.log
   curl -k  -X GET  -H "Authorization: Bearer ${access_token}" ${OAM_FQDN_AND_PORT}/oauth/v1/authn/users/profile | jq .
   exit 1
  fi


  log_info "### Renew password for ${user_name} ${user_pw}" | tee -a ccdm-prov-func-Init-Conf.log
  pw_renew_res=$(curl -k -i -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $access_token" -d "{\"username\":\"${user_name}@ericsson.com\",\"password\":$user_pw,\"new_password\":\"${password}\"}" ${OAM_FQDN_AND_PORT}/oauth/login/renew)
  debug $pw_renew_res
  if [[ $(echo ${pw_renew_res} |grep "204 No Content") != "" ]]
  then
    log_info "### Renew Authn User $user_name is successful." | tee -a ccdm-prov-func-Init-Conf.log
  else
    log_info "### Renew Authn User $user_name is failed!" | tee -a ccdm-prov-func-Init-Conf.log
    exit 1
  fi

  log_info "### Post Core User account:${user_name}" | tee -a ccdm-prov-func-Init-Conf.log
  post_core_res=$(curl -k -i -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $access_token" -d "{\"email\":\"${user_name}@ericsson.com\",\"user_info\":{\"given_name\":\"${user_name}\",\"family_name\":\"Ericsson\",\"account_type\":\"service_account\"},\"user_info_internal\":{\"roles\":[\"${role}\"]}}" ${OAM_FQDN_AND_PORT}/oauth/v1/users/profile)


  if [[ $(echo ${post_core_res} |grep '201 Created') != "" ]]
  then
    log_info "### Post Core User account $user_name is successful." | tee -a ccdm-prov-func-Init-Conf.log
  else
    log_info "### Post Core User account $user_name is failed!" | tee -a ccdm-prov-func-Init-Conf.log
    exit 1
  fi
done

echo "*************************************************************" | tee -a ccdm-prov-func-Init-Conf.log
echo "*************************************************************" | tee -a ccdm-prov-func-Init-Conf.log

log_info "### client_id:${client_id}" | tee -a ccdm-prov-func-Init-Conf.log
log_info "### client_secret:${client_secret}" | tee -a ccdm-prov-func-Init-Conf.log
log_info "### user:${users_list[0]}@ericsson.com ,password: ${password}" | tee -a ccdm-prov-func-Init-Conf.log
log_info "### user:${users_list[1]}@ericsson.com ,password: ${password}" | tee -a ccdm-prov-func-Init-Conf.log
log_info "### CCDM Provisioning Function Initial Configuration is successful." | tee -a ccdm-prov-func-Init-Conf.log

#curl -k  -X GET  -H "Authorization: Bearer ${access_token}" ${OAM_FQDN_AND_PORT}/oauth/v1/authn/users/profile | jq .

#log_info "### Get Core Users."
#curl -k  -X GET  -H "Authorization: Bearer ${access_token}" ${OAM_FQDN_AND_PORT}/oauth/v1/users/profile | jq .


