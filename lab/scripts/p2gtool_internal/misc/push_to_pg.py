from prometheus_client import CollectorRegistry, Gauge, Counter, push_to_gateway


def push_to_pg(metrics, job_name, pg_url):
    """Push metrics to Pushgateway
    :param metrics, list of dict, [metric1_dict, metric2_dict]
    Example of metrics data structure:
    [
        {
            "type": "Counter",
            "labels": [
                "card",
                "psc"
            ],
            "values": [
                [
                    [
                        "gc_0_19_1",
                        "psc_1"
                    ],
                    579
                ]
            ],
            "name": "Smf5gc_UpdateSmContextRsp500SYSTEM_FAILURE",
            "desc": "Smf5gc_UpdateSmContextRsp500SYSTEM_FAILURE"
        },
        {
            "name": "Non5gcDls_pps",
            "value": 2555,
            "desc": "Non5gcDls_pps",
            "type": "Gauge"
        }
    ]
    :param job_name, prometheus job name
    :param pg_url, Pushgateway base URL
    :return: return code of this function
    """
    registry = CollectorRegistry()
    RETVAL = True
    if collect_metrics(metrics, registry):
        try:
            push_to_gateway(pg_url, job=job_name, registry=registry)
        except:
            RETVAL = False
    else:
        RETVAL = False
    return RETVAL


def collect_metrics(metrics, registry):
    """Return Metric Class"""
    assert isinstance(metrics, list) and \
           isinstance(registry, CollectorRegistry)
    return all([_collect_metric(m, registry) for m in metrics])


def _collect_metric(metric, registry):
    """Collect metrics to registry"""
    RETVAL = True
    try:
        labels = metric.get('labels', [])
        if metric['type'] == "Counter":
            c = Counter(metric['name'],
                        metric['desc'],
                        labels,
                        registry=registry)
            if labels:
                for value in metric['values']:
                    c.labels(*value[0]).inc(value[1])
            else:
                c.set(metric['value'])
        elif metric['type'] == "Gauge":
            g = Gauge(metric['name'],
                      metric['desc'],
                      labels,
                      registry=registry)
            if labels:
                for value in metric['values']:
                    g.labels(*value[0]).set(value[1])
            else:
                g.set(metric['value'])
    except:
        RETVAL = False
    return RETVAL
