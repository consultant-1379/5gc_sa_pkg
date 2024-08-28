# Requirements

1. Python
2. The pyopenssl library.

```
pip install -r requirements.txt
```

# Usage


Description:
```pycon
ssl_cert_gen.py -h
usage: cd <base_dir>/5gc_sa_pkg;
       ssl_cert_gen -e n87 --cnfs sc ccsm

* SSL Certificate Generator *

optional arguments:
  -h, --help            show this help message and exit
  -e CLUSTER, --cluster CLUSTER
                        Determine the specific lab to generate SSL certificates.
                        if without it,would generate certificates for all labs.
                        
  --cnfs CNFS [CNFS ...]
                        Determine the CNF list to generate SSL certificates.
                        if without it, would generate certificates for all CNFs. 
                        example:--cnfs sc ccsm
                        
  -l, --list            Show the applicable lab list for generating SSL certificates.
                        with -e, show the applicable CNF list in the specific lab.
                        
  --ca-cert CA_CERT     The CA certificate file path for generating certificates,
                        default location: gerrit:5gc_sa_pkg/lab/certs/TeamBluesRootCA.crt,
                        it is not needed if the working dir is gerrit:5gc_sa_pkg
                        
  --ca-key CA_KEY       The CA key file path for generating certificates, 
                        default location: gerrit:5gc_sa_pkg/lab/certs/TeamBluesRootCA.key,
                        it is not needed if the working dir is gerrit:5gc_sa_pkg
                        
  --cert-source CERT_SOURCE
                        The source data file path for generating certificate files,
                        default location: gerrit:5gc_sa_pkg/lab/scripts/k8s/ssl_cert_generation/fivegcCertInfo.yml,
                        it is not needed if the working dir is gerrit:5gc_sa_pkg
                        
  --certs-dir CERTS_DIR
                        The directory for saving the generated certificate files,
                        if without it,would save certificates in the current directory

```

Example: generate the certificate & CA files

```
ssl_cert_gen.py --ca-cert=~/pc-git/5gc_sa_pkg/lab/certs/TeamBluesRootCA.crt --ca-key=~/pc-git/5gc_sa_pkg/lab/certs/TeamBluesRootCA.key --cert-source=~/PycharmProjects/SSLGeneration/fivegcCertInfo.yml --certs-dir=/tmp/fivegc_cert/
```

```
cd <base-dir>/5gc_sa_pkg
ssl_cert_gen.py  --certs-dir=/tmp/fivegc_cert/
ssl_cert_gen.py  -e n87 --cnfs ccsm sc
ssl_cert_gen.py  -e n87 

```
Achievement structure example:

```
fivegc_cert/
├── ccd
│   ├── ca.crt
│   └── ca.key
├── n28
│   ├── ccdm
│   │   ├── ccdm-iccr-server.crt
│   │   ├── ccdm-iccr-server.key
│   │   ├── ccdm-iccr-server.pfx
│   ├── ccsm
│   │   ├── ccsm-sbi-client.crt
│   │   ├── ccsm-sbi-client.key
│   │   ├── ccsm-sbi-client.pfx
│   ├── cnfs_pfx_data.yml
│    ...... 
├── n87
│   ├── ccdm
│    ...... 
└── n99
    ├── cces
    ......
```
NOTE
1. cnfs_pfx_data.yml contains all the p12 data of the lab i.e n28
2. The ca.crt&ca.key could be used for ECCD deployment 
