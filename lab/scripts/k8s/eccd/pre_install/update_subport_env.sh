#!/usr/bin/env bash
help()
{
    echo "Description: this script is used to update the eccd env file with corresponding subport network_id and vlan_id."
    echo "Usage: update_subport_env.sh -p <network prefix> -e <eccd env file> [ -d ]"
    echo "Example:"
    echo "for pure 5GC (prior TS 1.4), $0 -p eccd1 -e env-eccd1.yaml"
    echo "for dual mode, $0 -p eccd1 -e env-eccd1.yaml -d"
    exit 1
}

while getopts 'p:e:dh' OPT; do
    case $OPT in
        p) pref="$OPTARG";;
        e) env_file="$OPTARG";;
        d) dual_mode='true';;
        h) help;;
        ?) help;;
    esac
done

# 
echo 'Warning: NOT USED ANYMORE! PLS USE CEAT TOOL INSTEAD!!!'
exit 1

if [[ -z ${pref} ]] || [[ -z ${env_file} ]]; then
    echo "Error: need both -p and -e parameter"
    help
fi

if [[ "${dual_mode}" == "true" ]]; then
    networks=(
        "pc-mm-oam"
        "pc-mm-ran-1"
        "pc-mm-ran-2"
        "pc-mm-signaling-1"
        "pc-mm-signaling-2"
        "pc-mm-media"
        "pc-sm-signaling"
        "pc-sm-media"
        "pc-sm-intra"
        "pc-up-ran"
        "pc-up-signaling"
        "pc-up-media"
        "pc-up-dn"
        )
else
    networks=(
        "pc-mm-oam"
        "pc-mm-ran-1"
        "pc-mm-ran-2"
        "pc-mm-signaling"
        "pc-mm-media"
        "pc-sm-signaling"
        "pc-sm-media"
        "pc-sm-intra"
        "pc-up-ran"
        "pc-up-signaling"
        "pc-up-dn"
        )
fi    

sed -i '/network_id: /d;/vlan_id: /d' ${env_file}

for network in ${networks[@]}
do
    network_id=$(openstack network show ${pref}-${network} -f value -c id)
    vlan_id=$(openstack network segment list --network ${pref}-${network} -f value -c "Network Type" -c Segment | grep -m1 vlan | cut -d" " -f2)
    sed -i "/nicsets/i\        - network_id: ${network_id}" ${env_file}
    sed -i "/nicsets/i\          vlan_id: ${vlan_id}" ${env_file}
done
