#!/usr/bin/env python3

import os
import sys
import yaml
import argparse
import subprocess
import tempfile
import time

GET_CM_YAML = "kubectl {0} {1} get configmaps metallb-config -o yaml"
GET_CFG_YAML = "kubectl {0} {1} get configmaps metallb-config --template={{{{.data.config}}}}"
CREATE_CM = "kubectl {0} {1} create configmap metallb-config --from-file config -o yaml --dry-run=client"
APPLY_FILE = "kubectl {0} apply -f -"

parser = argparse.ArgumentParser()
actions = parser.add_mutually_exclusive_group()
actions.add_argument('-i', '--insert', dest='ins_name', help="")
actions.add_argument('-d', '--delete', dest='del_name', help="")
parser.add_argument('-c', dest='cluster', help="k8s cluster name")
parser.add_argument('-n', dest='ns', default='kube-system', help="k8s cluster name")
parser.add_argument('--ip', dest='addr', help="Address")
parser.add_argument('--cpn', dest='colpoolname', help="Collocated address pool name in the same my-address-pools")

opts = parser.parse_args()

kubeconfig_opt = ''
if opts.cluster:
    kubeconfig_opt = f"--kubeconfig=/lab/pccc_utils/scripts/src/kubeconfig/{opts.cluster}.config"
ns_opt = f"-n {opts.ns}"

get_cm_cmd = GET_CM_YAML.format(kubeconfig_opt, ns_opt)
get_cfg_cmd = GET_CFG_YAML.format(kubeconfig_opt, ns_opt)
update_cm_cmd = f"{CREATE_CM.format(kubeconfig_opt, ns_opt)} | {APPLY_FILE.format(kubeconfig_opt)}"

bak_file = os.path.join(os.path.expanduser('~'), '{0}_metallb-config_{1}.yaml'.format(opts.cluster, time.strftime('%Y%m%d%H%M%S')))
print(f"Backup the configmap yaml to {bak_file}")
p = subprocess.run(get_cm_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8")
if p.returncode != 0:
    sys.exit(1)
else:
    with open(bak_file, 'w') as f:
        f.write(p.stdout)

tmp_dir = tempfile.TemporaryDirectory()
os.chdir(tmp_dir.name)

p = subprocess.run(get_cfg_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8")

if p.returncode != 0:
    sys.exit(1)

lb_cfg = yaml.safe_load(p.stdout)
with open('config-old', 'w') as f:
    yaml.dump(lb_cfg, f, default_flow_style=False)

if opts.ins_name:
    pool_name = opts.ins_name
    for pool in lb_cfg['address-pools']:
        if pool['name'] == pool_name:
            print(f"Error: address pool name '{pool_name}' already exists:\n{yaml.dump(pool, default_flow_style=False)}")
            sys.exit(1)
        elif pool['addresses'][0] == f"{opts.addr}/32":
            print(f"Error: address '{opts.addr}' already exists:\n{yaml.dump(pool, default_flow_style=False)}")
            sys.exit(1)
    if len(lb_cfg['bgp-bfd-peers']) > 1 and opts.colpoolname is None:
        print(f"Error: metallb is configured as traffic separation, please provide the address pool name using '--cpn' to put the new pool '{pool_name}' together")
        sys.exit(1)
    
    new_pool = {}
    new_pool['name'] = pool_name
    new_pool['addresses'] = [ f"{opts.addr}/32" ]
    new_pool['auto-assign'] = False
    new_pool['protocol'] = 'bgp'

    print(f"Appending address pool: {new_pool} to 'address-pools'")
    lb_cfg['address-pools'].append(new_pool)

    cpn_found = 0
    if len(lb_cfg['bgp-bfd-peers']) > 1:
        for peer in lb_cfg['bgp-bfd-peers']:
            if opts.colpoolname in peer['my-address-pools']:
                print(f"Appending '{pool_name}' to 'my-address-pools' together with '{opts.colpoolname}'")
                peer['my-address-pools'].append(pool_name)
                cpn_found = 1
                break
        if cpn_found == 0:
            print(f"Error: the provided address pool name '{opts.colpoolname}' doesn't exist")
            sys.exit(1)

    with open('config', 'w') as f:
        yaml.dump(lb_cfg, f, default_flow_style=False)

elif opts.del_name:
    pool_name = opts.del_name
    pool_found = 0
    for pool in lb_cfg['address-pools']:
        if pool['name'] == pool_name:
            print(f"Removing address pool: {pool} from 'address-pools'")
            lb_cfg['address-pools'].remove(pool)
            pool_found = 1
            break
    if pool_found == 0:
        print(f"Error: address pool name '{pool_name}' doesn't exist")
        sys.exit(1)
    if len(lb_cfg['bgp-bfd-peers']) > 1:
        for peer in lb_cfg['bgp-bfd-peers']:
            if pool_name in peer['my-address-pools']:
                print(f"Removing '{pool_name}' from 'my-address-pools'")
                peer['my-address-pools'].remove(pool_name)
                break
    with open('config', 'w') as f:
        yaml.dump(lb_cfg, f, default_flow_style=False)

else:
    parser.print_help()

print("Applying the configmap changes ...")
p = subprocess.run(update_cm_cmd, shell=True)
if p.returncode == 0:
    print("metallb-config was updated successfully, please double check the new configmap. Restore the configmap using the backup if anything wrong.")
else:
    print("Error: failed to update the metallb-config")