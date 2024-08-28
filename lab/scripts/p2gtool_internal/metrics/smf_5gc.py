#!/usr/bin/env python

import re
from paramiko_ssh import cre_ssh


def gen_pdu_n11_res_metrics(hostname, username, password, prefix="Smf5gc",
                            instance=""):
    command = 'epg node internal-debug execute cmd-string "show istats pdu"'
    outputs = cre_ssh(hostname, username, password, command)
    pattern = re.compile(r'-{22}\r\n(gc-[0-9]+/[0-9]+/[0-9]+\s\(psc-[01]\))'
                         r'.*?(pdu.n11.outgoing.response\r\n(\s\s[^(\r\n)]+:'
                         r'(-?|[^\s\r\n]+)\s+[0-9]+\r\n)+)', re.DOTALL)
    metrics = []
    value_dict = {}
    labels_dict = {'instance': instance}
    for m in pattern.findall(outputs):
        labels_dict['card'] = \
            m[0].split()[0].replace('/', '_').replace('-', '_')
        labels_dict['psc'] = \
            m[0].split()[1].strip('()').split('-')[1]
        for line in m[1].splitlines():
            if len(line.split()) > 1:
                name = '{0}_{1}'.format(
                    prefix,
                    line.split()[0].strip(' ').replace(':', '').strip('-'))
                value = int(line.split()[1])
                value_dict.setdefault(name, [])
                value_dict[name].append([list(labels_dict.values()), value])

    for k, v in value_dict.items():
        metrics.append(dict(name=k,
                            values=v,
                            desc=k,
                            type="Counter",
                            labels=list(labels_dict.keys())))
    return metrics
