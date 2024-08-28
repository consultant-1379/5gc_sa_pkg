#!/usr/bin/env python

from utils import get_active_alarms


def gen_actAlarms_metrics(pod, cluster="eccd1", prefix="dm5gc", instance=""):
    """
    """

    outputs = get_active_alarms(pod, cluster)
    metrics = []
    value_dict = {}
    labels_dict = {'instance': instance}
    name = '{0}_{1}'.format(
        prefix,
        'alarms')
    for m in outputs:
        labels_dict["namespace"] = m["namespace"]
        labels_dict["status"] = m["status"]
        labels_dict["cluster"] = m.get("cluster", "eccd1")
        value_dict.setdefault(name, [])
        value_dict[name].append([list(labels_dict.values()), len(m["alarms"])])

    for k, v in value_dict.items():
        metrics.append(dict(name=k,
                            values=v,
                            desc=k,
                            type="Gauge",
                            labels=list(labels_dict.keys())))
    return outputs, metrics
