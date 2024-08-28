#!/usr/bin/env python

from nrfclient import nrf


def gen_nfStatus_metrics(pod, prefix="NrfInfo", instance=""):
    outputs = nrf.Nrf(pod).query_nf_status()
    #outputs = [
    #    {
    #        "nfType": "UDR",
    #        "nfStatus": "REGISTERED",
    #        "nfServices": [
    #            {
    #                "nfServiceStatus": "REGISTERED",
    #                "nfServiceName": "nudr-dr"
    #            }
    #        ]
    #    },
    #    {
    #        "nfType": "AUSF",
    #        "nfStatus": "REGISTERED",
    #        "nfServices": [
    #            {
    #                "nfServiceStatus": "REGISTERED",
    #                "nfServiceName": "nausf-auth"
    #            }
    #        ]
    #    }]

    metrics = []
    value_dict = {}
    labels_dict = {'instance': instance}
    status_code = {"REGISTERED": 1,
                   "SUSPENDED": 2}
    unregister_code = 0
    name = '{0}_{1}'.format(
        prefix,
        'nfstatus')
    labels_dict['nfServiceName'] = "self"
    for m in outputs:
        labels_dict['nfType'] = m['nfType']
        value_dict.setdefault(name, [])
        value_dict[name].append([list(labels_dict.values()), status_code.get(m["nfStatus"], unregister_code)])
        for i in m.get('nfServices', []):
            #name = '{0}_{1}'.format(
            #    prefix,
            #    m["nfType"])
            labels_dict['nfServiceName'] = i["nfServiceName"]
            value = int(status_code.get(i["nfServiceStatus"], unregister_code))
            #value_dict.setdefault(name, [])
            value_dict[name].append([list(labels_dict.values()), value])

    for k, v in value_dict.items():
        metrics.append(dict(name=k,
                            values=v,
                            desc=k,
                            type="Gauge",
                            labels=list(labels_dict.keys())))
    return metrics
