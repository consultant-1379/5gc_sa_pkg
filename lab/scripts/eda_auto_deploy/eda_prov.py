#!/usr/bin/python3
import os
import re
import json
import sys
import requests
import argparse
sys.path.append(r'/home/eluxlin/Project/lib/')
import yaml
import urllib3
import time
from requests.packages.urllib3.exceptions import InsecureRequestWarning
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)


###parase where and what to provision
parser = argparse.ArgumentParser()
parser.add_argument("-e", "--eda",
                    type=str,
                    required=True,
                    help="specify which eda do provisioning ,  example: n84-eccd1, n67-eccd1")
parser.add_argument("-n", "--ne",
                    type=str,
                    required=False,
                    help="Path for  Networkelement config files")
parser.add_argument("-r", "--routing",
                    type=str,
                    required=False,                  
                    help="Path for routing config files ")
args = parser.parse_args()
eda = args.eda
eda_info = {
"n99-eccd1": "https://oam.eda.n99-eccd1.sero.gic.ericsson.se",
"n28-eccd1": "https://oam.eda.n28-eccd1.sero.gic.ericsson.se",
"n280-eccd1": "https://oam.eda1-oam.n280-eccd1.sero.gic.ericsson.se",
"n67-eccd1": "https://oam.eda2.n67-eccd1.sero.gic.ericsson.se",
"n84-eccd1": "https://oam.eda2.n84-eccd1.sero.gic.ericsson.se",
"pod56-eccd1": "https://oam.eda.pod56-eccd1.seln.ete.ericsson.se"
}






#Prov_eda="https://oam.eda2.n84-eccd1.sero.gic.ericsson.se" 
Prov_eda=eda_info[eda]
Prov_ne=Prov_eda + "/cm-rest/v1/network-elements"
Prov_routing=Prov_eda + "/cm-rest/v1/routings"
Prov_group=Prov_eda + "/cm-rest/v1/network-element-groups"
###################################http post operation###########################
def eda_request(Url, Headers, Data, Operation="POST"):
    response = requests.request(Operation, Url, verify=False, headers=Headers,data=Data)
#    print( response.status_code,Operation,response.text,Data,Url)
    if int(response.status_code) >= 300:       
      if response.text == '{"message":"Failed to find given resource"}':
          return(response)
      elif response.text == '{"message":"The role with the id All already exists"}':
          return(response)
      elif re.findall("network-elements",Url):
          return(response)
      elif re.findall("routings",Url):
          return(response)       
      else:
          print("http response code is %s process quit"%response.status_code,end = '. ' )     
          print("Response text is %s"%response.text)
          exit(1)
    else:
       return(response)

############################Request Token#########################################
def Token_request(Username,Password,client_id,client_secrert):  
  headers = {
    'Content-Type': 'application/x-www-form-urlencoded'
  }
 
  Token_url= Prov_eda + "/oauth/v1/token?grant_type=password&client_id=" + client_id + "&client_secret=" + client_secrert + "&username=" + Username + "&password=" + Password + "&scope=openid scopes.ericsson.com/activation/oauth.authn.user.read scopes.ericsson.com/activation/oauth.authn.user.write scopes.ericsson.com/activation/oauth.core.user.read scopes.ericsson.com/activation/oauth.core.user.write scopes.ericsson.com/activation/oauth.core.client.read scopes.ericsson.com/activation/oauth.core.client.write scopes.ericsson.com/activation/roles.read scopes.ericsson.com/activation/roles.write scopes.ericsson.com/activation/roles.read scopes.ericsson.com/activation/roles.write scopes.ericsson.com/activation/network_element_management.read scopes.ericsson.com/activation/network_element_management.write"
  try:
    response=eda_request(Token_url, headers, Data={}, Operation="POST")
    Token=json.loads(response.text)["access_token"]
    print("Token is "+ Token)
    return(Token)
  except:
     print(response.text)
     exit(1)          

    
if os.path.exists(os.getcwd()+"/credential.yaml" ):
  print("credential.yaml already exists, skip account provisioning ， go to NE and Routing provisioning.\n\
For first time Provisioning, please remove credential.yaml first.") 
  pass
else:
   
   
    
  ###########################prov day0 accounts####################################
  print("###########################prov day0 accounts####################################")
  headers = {
    'Content-Type': 'application/json'
  }
  Prov_day0=Prov_eda + "/oauth/v1/onboard"
  f=open("./eda.yaml",'r',encoding='UTF-8')
  Day0_load=yaml.safe_load(f.read())
  f.close()
  Day0_accounts_yaml=Day0_load["day0"]
  print(Day0_accounts_yaml)
  Day0_accounts=json.dumps(Day0_accounts_yaml)
  Username=Day0_accounts_yaml["service_account"][0]["user_name"]
  Password=Day0_accounts_yaml["service_account"][0]["password"]
  try:
    response = eda_request(Prov_day0, headers, Day0_accounts, Operation="POST")
    client_id=json.loads(response.text)["clients"][0]["client_id"]
    client_secrert=json.loads(response.text)["clients"][0]["client_secret"]   
    print(response.text)
  except:
    #response = eda_request(Prov_day0, headers, Day0_accounts, Operation="POST")
    print("Error happen , process exits" + response.status_code + response.text)
    exit(1)



  #Username="admin@ericsson.com"
  #Password="Password!1234" 
  #client_id="29e638f0-6ef5-11ed-9933-19c5a5807e2c"
  #client_secrert="1b52b88a-1c6c-42f3-b0d2-600c60be3cef"
  ##############################Create roles with all permission#######################
  Token=Token_request(Username,Password,client_id,client_secrert)     
  print("############################Create roles with all permission######################")
  headers = {
  'Content-Type': 'text/plain',
  'Authorization': 'bearer ' + Token
  }
  
  f=open("./eda.yaml",'r')
  Day1=yaml.safe_load(f.read())
  Day1_role=Day1["role"]
  Allroles=json.dumps(Day1_role)
  Prov_role=Prov_eda + "/accessrules/v1/roles"
  try:
    response=eda_request(Prov_role, headers, Data=Allroles, Operation="POST")
    if response.text == '{"message":"The role with the id All already exists"}':
      print("The role with the id All already exists")
      pass
    else:
      print("Complete Role creation successfully")
  except:
    print(response.text) 
    exit(1) 
    
  #############################provisioning a service account #######################
  print("############################provisioning a service account #######################")
  Prov_svc_url=Prov_eda + "/oauth/v1/authn/users/profile"
  
  Prov_svc_account={	"email": "abcd1234@eda.local",	"lockable": "true",\
            	"locked": "false",	"password": "Password!1234",	"user_info": { "account_type": "service_account"	},	"user_name": "abcd1234"  }
  Prov_svc_account["email"]=Day1["serviceaccount"]["username"]
  Prov_svc_account["password"]=Day1["serviceaccount"]["password"]
  Prov_svc_account["user_name"]=Day1["serviceaccount"]["username"]
  
  Prov_svc=json.dumps(Prov_svc_account)
  
  try:
    response=eda_request(Prov_svc_url, headers, Data=Prov_svc, Operation="POST")
    print('Complete service account %s creation'%Prov_svc_account["user_name"])
  except:
     print("failed to provision service account %s"%Prov_svc_account["user_name"] + response.text) 
     exit(1) 
    
  
  ##############################provisioning role for the service account #############
  print("############################provisioning role for the service account ############")
  Prov_svc_role_url= Prov_eda + "/oauth/v1/users/profile"
  
  Prov_svc_role={\
  	"email": "abcd1234@eda.local",\
  	"user_info": {\
  	  "account_type": "service_account"\
  	},\
  	"user_info_internal": {\
  	  "access_groups": [\
  		"Full Authority"\
  	  ],\
  	  "admin_domain": [],\
  	  "description": "abcd1234",\
  	  "max_cai_sessions": 0,\
  	  "max_cai3g_sessions": 0,\
  	  "max_mml_sessions": 0,\
  	  "max_ssh_sessions": 0,\
  	  "min_HLR_sustainable": 0,\
  	  "public_key": "",\
  	  "roles": [\
  		"allrights"\
  	  ]\
  	}\
    }
     
  Prov_svc_role["email"]=Day1["serviceaccount"]["username"]
  Prov_svc_role["description"]=Day1["serviceaccount"]["username"]
  Prov_svc=json.dumps(Prov_svc_role)
  
  
  try:
    response=eda_request(Prov_svc_role_url, headers, Data=Prov_svc, Operation="POST")
    print('Complete role provisioning for service account %s authorization'%Prov_svc_account["user_name"])
    ###write credential file 
    ServiceUser=Day1["serviceaccount"]["username"]
    ServicePass=Day1["serviceaccount"]["password"]
    credential={"ServiceUser": ServiceUser, "ServicePass": ServicePass , "client_id": client_id,"client_secrert": client_secrert}
    Location=os.getcwd() + "/credential.yaml"
    with open(Location, 'w', encoding='utf-8') as f:
      f.write(yaml.dump(credential))
      f.close()
  except:
     print("failed to provision roles for service account %s"%Prov_svc_account["user_name"] + response.text) 
     exit(1) 
    
     
  #############################provisioning a user account #######################
  print("############################provisioning a user account ##########################") 
  Prov_user_url=Prov_eda + "/oauth/v1/authn/users/profile"
  
  Prov_user_account={"email":"a@ericsson.com","user_info":{"family_name":"","given_name":"","phone_number":"",\
          "region_code_name":"Country","region_code_title":"Country","region_code_value":""},"user_name":"a@ericsson.com"}
  Prov_user_account["email"]=Day1["useraccount"]["username"]
  Prov_user_account["user_name"]=Day1["useraccount"]["username"]
  Prov_user=json.dumps(Prov_user_account)
  
  
  try:
    response=eda_request(Prov_user_url, headers, Data=Prov_user, Operation="POST")
    print('Complete user account %s creation  '%Prov_user_account["user_name"])
    User_password=json.loads(response.text)["password"]
    print("Don't forget to change the initial Password %s for account %s"%(User_password,Prov_user_account["user_name"]))  
    Location=os.getcwd() + "/credential.yaml"
    with open(Location, 'w', encoding='utf-8') as f:
      f.write(yaml.dump(credential))
      f.close()
  except:
    print("failed to provision user account %s"%Prov_user_account["user_name"] + response.text) 
    exit(1) 
  
  #############################provisioning role for  user account #############
  print("############################provisioning role for  user account ##################")   
  Prov_user_role_url= Prov_eda + "/oauth/v1/users/profile"
  
  Prov_user_role={"email":"a@ericsson.com","user_info":{"family_name":"","given_name":"","phone_number":"",\
          "region_code_name":"Country","region_code_title":"Country","region_code_value":""},\
              "user_info_internal":{"roles":"[\"allrights\",\"Default role\"]"}}
     
  Prov_user_role["email"]=Day1["useraccount"]["username"]
  Prov_user_role["description"]=Day1["useraccount"]["username"]
  Prov_user=json.dumps(Prov_user_role)
  
  
  try:
    response=eda_request(Prov_user_role_url, headers, Data=Prov_user, Operation="POST")
    print('Complete role provisioning for user account %s authorization'%Prov_user_account["user_name"])
  except:
    print("failed to provision role for user account %s"%Prov_user_account["user_name"] + response.text) 
    exit(1) 

#####################################Read credential file##########################################
Cred_location=os.getcwd()+"/credential.yaml"    
f=open(Cred_location,'r')
Cred=yaml.safe_load(f.read())
f.close()
ServiceUser=Cred["ServiceUser"]
ServicePass=Cred["ServicePass"]
client_id=Cred["client_id"]
client_secrert=Cred["client_secrert"]
Token=Token_request(ServiceUser,ServicePass,client_id,client_secrert) 
headers = {
'Content-Type': 'text/plain',
'Authorization': 'bearer ' + Token
}      
print("#####################################Provision NE##########################################")

Ne_location=os.getcwd() + "/nes/"
for key in os.listdir(Ne_location):
  if re.match(r".*.node",key):
    f=open(Ne_location+key,'r')
    print(key)
    Ne_data = json.load(f)
    Ne_name = Ne_data["name"]
    Ne_del = Prov_ne+"/"+Ne_name
    Ne=json.dumps(Ne_data)
    print("Start the Ne Provisioning for " + Ne_name)  
    i=0  ###a counter for while loop
    # try:
    #   response=eda_request(Ne_del, headers, {}, Operation="DELETE")
    # except:
    #   pass
    while True:
      i=i+1
      if i > 6:
        print("Tried more than 6 times,NE provisioning Error for "+ Ne_name +  response.text)
        break
      else:
        response=eda_request(Prov_ne, headers, Ne, Operation="POST")
        if response.status_code < 300:
          print("Complete the Ne Provisioning for " + Ne_name)  
          break
        else:
          print(response.status_code ,response.text,end=' ')
          print("sleep 10s")
          time.sleep(10)
          continue
f.close()       
  

#####################################Provision Group##########################################
print("#####################################Provision  NE Groups##########################################")
group_location=os.getcwd() + "/groups/"
for key in os.listdir(group_location):
  if re.match(r".*.group",key):
    try:
      f=open(group_location+"/"+key,'r')
      group_data = json.load(f)
      group_name =  group_data["name"]
      group=json.dumps(group_data)
      response=eda_request(Prov_group, headers, group, Operation="POST")
      if response.status_code >= 300:
        print("group provisioning Error for "+group +  response.text)
      else:
        print("Complete the Routing Provisioning for " + group_name)
    except:
      print("Routing provisioning Error for " + group_name)
f.close()


#####################################Provision Routing##########################################
print("#####################################Provision Routing##########################################")
Routing_location=os.getcwd() + "/routings/"        
for key in os.listdir(Routing_location):
  if re.match(r".*.routing",key):
    try:
      f=open(Routing_location+"/"+key,'r')
      routing_data = json.load(f)
      routing_name =  routing_data["networkElementType"]
      routing=json.dumps(routing_data)
      response=eda_request(Prov_routing, headers, routing, Operation="POST")
      if response.status_code >= 300:
        print("Routing provisioning Error for "+routing_name +  response.text)
      else:
        print("Complete the Routing Provisioning for " + routing_name)  
    except:
      print("Routing provisioning Error for " + routing_name)
f.close()
