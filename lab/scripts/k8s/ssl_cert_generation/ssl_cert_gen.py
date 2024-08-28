#!/lab/pccc_utils/scripts/csdp_python3_venv/bin/python

import argparse
import os.path
import random
import sys
import textwrap
from os import path, makedirs

import yaml
from OpenSSL import crypto

CERT_FILE_SUFFIX = '.crt'
PRIVATE_KEY_FILE_SUFFIX = '.key'
CNFS_P12_DATA_IN_LAB = 'cnfs_p12_data.yml'


def read_cert_data_from_yaml(file_path):
    try:
        with open(file=file_path, mode='r', encoding="utf-8") as f:
            return yaml.full_load(f)
    except OSError as e:
        print("Error: Failed to open certificate yaml file %s, reason:%s" % (file_path, e))
        sys.exit(1)


class SSLCertificateGenerator:
    key_dir = None
    index_file = None
    serial = None
    ca_cert_path = None
    ca_key_path = None
    working_dir = None
    passphrase = None

    country = "SE"
    state = "Stockholm"
    localityName = "Stockholm"
    certOrganization = "Ericsson"
    certOrganizationUnit = "vepc"

    def __init__(self, key_dir=None, ca_cert_path=None, ca_key_path=None):
        # Define key_dir
        if key_dir:
            key_dir = key_dir.replace('\\', '/')
            if not path.isdir(key_dir):
                # raise Exception("Key Directory does not exist or is not a directory:" + key_dir)
                os.makedirs(key_dir)
        else:
            key_dir = path.dirname(path.realpath(__file__)) + "/keys"
            key_dir = key_dir.replace('\\', '/')

        self.key_dir = key_dir

        self.index_file = key_dir + '/index.txt'
        self.ca_cert_path = ca_cert_path
        self.ca_key_path = ca_key_path

    def _get_cert_dn(self, cert):
        dn = ''
        for label, value in cert.get_subject().get_components():
            dn += '/' + label + '=' + value

        return dn

    def _gen_key(self):
        # Generate new key
        key = crypto.PKey()
        key.generate_key(crypto.TYPE_RSA, 2048)
        return key

    def _create_csr(self, cert_name, key):
        req = crypto.X509Req()
        req.get_subject().CN = cert_name
        req.set_pubkey(key)
        req.sign(key, "sha256")
        return req

    def _write_key_to_file(self, key, filepath):
        key_file = open(filepath, 'w')
        key_file.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, key).decode("utf-8"))
        key_file.close()

    def _load_key_from_file(self, filepath):
        key_file = open(filepath, 'r')
        key = crypto.load_privatekey(crypto.FILETYPE_PEM, key_file.read())
        key_file.close()
        return key

    def _write_cert_to_file(self, cert, filepath):
        cert_file = open(filepath, 'w')
        cert_file.write(crypto.dump_certificate(crypto.FILETYPE_PEM, cert).decode("utf-8"))
        cert_file.close()

    def _load_cert_from_file(self, filepath):
        cert_file = open(filepath, 'r')
        cert = crypto.load_certificate(crypto.FILETYPE_PEM, cert_file.read().encode("utf-8"))
        cert_file.close()
        return cert

    def _write_csr_to_file(self, csr, filepath):
        csr_file = open(filepath, 'w')
        csr_file.write(crypto.dump_certificate_request(crypto.FILETYPE_PEM, csr).decode("utf-8"))
        csr_file.close()

    def _load_csr_from_file(self, filepath):
        csr_file = open(filepath, 'r')
        csr = crypto.load_certificate_request(crypto.FILETYPE_PEM, csr_file.read().encode("utf-8"))
        csr_file.close()
        return csr

    def _write_pfx_to_file(self, pkcs12, filepath, passphrase=None):
        pkcs12_file = open(filepath, 'wb')
        pkcs12_file.write(pkcs12.export(passphrase))
        pkcs12_file.close()

    def _write_crl_to_file(self, crl, ca_cert, ca_key, filepath):
        # Write CRL file
        crl_file = open(filepath, 'w')
        crl_file.write(crl.export(ca_cert, ca_key, days=365).decode("utf-8"))
        crl_file.close()

    def _load_crl_from_file(self, filepath):
        try:
            crl_file = open(filepath, 'r')
            crl = crypto.load_crl(crypto.FILETYPE_PEM, crl_file.read())
            crl_file.close()
        except IOError:
            # Create new CRL file if it doesn't exist
            crl = crypto.CRL()

        return crl

    def _sign_csr(self, req, ca_key, ca_cert, common_name, cert_org=None, cert_ou=None, usage=1, days=3650,
                  alt_names=[]):
        expiry_seconds = days * 86400

        # Create and sign certificate
        cert = crypto.X509()
        cert.set_version(2)
        cert.set_subject(req.get_subject())
        if cert_org is not None:
            cert.get_subject().O = cert_org
        else:
            cert.get_subject().O = ca_cert.get_subject().O
        if cert_ou is not None:
            cert.get_subject().OU = cert_ou
        else:
            cert.get_subject().OU = ca_cert.get_subject().OU
        cert.set_serial_number(random.getrandbits(160))
        cert.gmtime_adj_notBefore(0)
        cert.gmtime_adj_notAfter(expiry_seconds)
        cert.set_issuer(ca_cert.get_subject())
        cert.set_pubkey(req.get_pubkey())

        cert.get_subject().C = self.country
        cert.get_subject().ST = self.state
        cert.get_subject().L = self.localityName
        cert.get_subject().CN = common_name
        if usage == 1:
            cert.add_extensions([
                crypto.X509Extension(b"basicConstraints", False, b"CA:FALSE"),
                crypto.X509Extension(b"keyUsage", False, b"digitalSignature, nonRepudiation, keyEncipherment"),
                crypto.X509Extension(b"extendedKeyUsage", False, b"serverAuth, clientAuth"),
                crypto.X509Extension(b"subjectKeyIdentifier", False, b"hash", subject=cert)
            ])
        elif usage == 2:
            cert.add_extensions([
                crypto.X509Extension(b"extendedKeyUsage", True, b"serverAuth"),
            ])
        elif usage == 3:
            cert.add_extensions([
                crypto.X509Extension(b"extendedKeyUsage", True, b"clientAuth"),
            ])

        # Add alt names
        if alt_names:
            for name in alt_names:
                name = "DNS:" + name
            cert.add_extensions([
                crypto.X509Extension(b"subjectAltName", False, b"DNS:" + ",DNS:".join(alt_names).encode("utf-8"))
            ])

        cert.sign(ca_key, "sha256")
        return cert

    def gen_ca(self, cert_org="Universe", cert_ou="Galaxy", days=3650):
        expiry_seconds = days * 86400

        # Generate key
        key = crypto.PKey()
        key.generate_key(crypto.TYPE_RSA, 2048)

        # Set up and sign CA certificate
        ca = crypto.X509()
        ca.set_version(2)
        ca.set_serial_number(random.getrandbits(160))
        ca.get_subject().CN = "CA"
        ca.get_subject().O = cert_org
        ca.get_subject().OU = cert_ou
        ca.gmtime_adj_notBefore(0)
        ca.gmtime_adj_notAfter(expiry_seconds)
        ca.set_issuer(ca.get_subject())
        ca.set_pubkey(key)
        ca.add_extensions([
            crypto.X509Extension(b"basicConstraints", True, b"CA:TRUE, pathlen:0"),
            crypto.X509Extension(b"keyUsage", True, b"keyCertSign, cRLSign"),
            crypto.X509Extension(b"subjectKeyIdentifier", False, b"hash", subject=ca)
        ])
        ca.sign(key, "sha256")

        ca_dir = self.key_dir + os.path.sep + 'ccd'
        if not os.path.exists(ca_dir):
            os.makedirs(ca_dir)
        # Write CA certificate to file
        self._write_cert_to_file(ca, self.key_dir + os.path.sep + 'ccd' + os.path.sep + 'ca.crt')

        # Write CA key to file
        self._write_key_to_file(key, self.key_dir + os.path.sep + 'ccd' + os.path.sep + 'ca.key')
        print("INFO: The CA files for CCD are saved in %s" % ca_dir)

    def gen_cert(self, cert_name, common_name, usage=1, days=3650, alt_names=[],
                 target_dir="/tmp"):
        # usage: 1=ca, 2=server, 3=client
        if cert_name == "":
            raise Exception("Certificate name cannot be blank")

        if not path.exists(target_dir):
            makedirs(target_dir)

        # Load CA certificate
        ca_cert = self._load_cert_from_file(self.ca_cert_path)

        # Load CA key
        ca_key = self._load_key_from_file(self.ca_key_path)

        # Generate new key
        key = self._gen_key()

        # Create CSR
        req = self._create_csr(cert_name, key)

        # Sign CSR
        cert = self._sign_csr(req, ca_key, ca_cert, common_name=common_name, cert_org=self.certOrganization,
                              cert_ou=self.certOrganizationUnit,
                              usage=usage, days=days,
                              alt_names=alt_names)

        # Write new key file
        self._write_key_to_file(key, target_dir + os.path.sep + cert_name + PRIVATE_KEY_FILE_SUFFIX)

        # Write new certificate file
        self._write_cert_to_file(cert, target_dir + os.path.sep + cert_name + CERT_FILE_SUFFIX)

    def gen_pfx(self, cert_name, cert_dir, passphrase=None):
        if cert_name == "":
            raise Exception("Certificate name cannot be blank")

        # # Load CA certificate
        # ca_cert = self._load_cert_from_file(self.ca_cert_path)

        # Load Certificate
        cert = self._load_cert_from_file(cert_dir + os.path.sep + cert_name + CERT_FILE_SUFFIX)

        # Load Private Key
        key = self._load_key_from_file(cert_dir + os.path.sep + cert_name + PRIVATE_KEY_FILE_SUFFIX)

        # Set up PKCS12 structure
        pkcs12 = crypto.PKCS12()
        # pkcs12.set_ca_certificates([ca_cert])
        pkcs12.set_certificate(cert)
        pkcs12.set_privatekey(key)

        # Write PFX file
        self._write_pfx_to_file(pkcs12, cert_dir + os.path.sep + cert_name + '.p12', passphrase)
        os.system('printf %s ' + cert_name + ': >>' +
                  self.working_dir + os.path.sep + CNFS_P12_DATA_IN_LAB)
        os.system('cat ' + cert_dir + os.path.sep + cert_name + '.p12 |base64 -w0 >> ' +
                  self.working_dir + os.path.sep + CNFS_P12_DATA_IN_LAB)
        os.system('echo >> ' +
                  self.working_dir + os.path.sep + CNFS_P12_DATA_IN_LAB)

    def gen_certs_from_data_source(self, cert_data, cnfs=[]):
        for lab_name in cert_data.keys():
            if len(cnfs) == 0:
                print("INFO: As argument '--cnfs' is not provided, would generate certificates for all the CNFs "
                      "in lab %s." % lab_name)
                selected_cnfs = list(cert_data[lab_name].keys())
            else:
                all_cnf_exist_flag = True
                for i in cnfs:
                    if i not in list(cert_data[lab_name].keys()):
                        print("ERROR: The provided CNF: %s by argument '--cnfs' "
                              "does not exist in lab %s" % (i, lab_name))
                        all_cnf_exist_flag = False

                if not all_cnf_exist_flag:
                    print("ERROR: The expected CNF list in lab %s is: %s"
                          % (lab_name, list(cert_data[lab_name].keys())))
                    sys.exit(1)

                selected_cnfs = cnfs
            print("INFO: Start generating certificates for lab:%s" % lab_name)
            self.working_dir = self.key_dir + os.path.sep + lab_name
            os.system("rm -rf " + self.working_dir)
            for cnf in selected_cnfs:

                working_dir_cnf = self.working_dir + os.path.sep + cnf
                if not os.path.exists(working_dir_cnf):
                    os.makedirs(working_dir_cnf)

                for cert_item in cert_data[lab_name][cnf]:
                    print("INFO: generate certificates:%s for :%s-%s" % (cert_item['cert_name'], lab_name, cnf))
                    self.gen_cert(cert_name=cert_item['cert_name'],
                                  common_name=cert_item['cn'],
                                  alt_names=cert_item['subjectAlternateName'],
                                  target_dir=working_dir_cnf)
                    self.gen_pfx(cert_name=cert_item['cert_name'], cert_dir=working_dir_cnf, passphrase=self.passphrase)

            print("INFO: All the pfx(p12) data of %s are saved in %s" %
                  (lab_name, self.working_dir + os.path.sep + CNFS_P12_DATA_IN_LAB))
        print("INFO: ########################################################")
        print("INFO: All the certificates are saved in %s" % self.key_dir)
        print("INFO: ########################################################")


def list_provided_info_from_cert_source(cert_source_data, parser):
    args = parser.parse_args()
    if args.list:
        print(parser.description)
        if args.cluster:
            print("INFO: The applicable CNF list in lab %s:" % args.cluster, end='')
            for cnf in cert_source_data["lab"][args.cluster].keys():
                print(cnf, end=' ')
            print()
        else:
            print("INFO: The applicable lab list: ", end='')
            for lab in cert_source_data["lab"].keys():
                print(lab, end=' ')
            print()

        sys.exit(0)


def build_arguments():
    inner_parser = argparse.ArgumentParser(usage="cd <base_dir>/5gc_sa_pkg;"
                                           "\n       ssl_cert_gen -e n280 --cnfs sc ccsm",
                                           description='* SSL Certificate Generator *',
                                           formatter_class=argparse.RawTextHelpFormatter)

    inner_parser.add_argument('-e', '--cluster', type=str,
                              required=False, help=textwrap.dedent(
            '''\
            Determine the specific lab to generate SSL certificates.
            if without it,would generate certificates for all labs.
            \n'''))

    inner_parser.add_argument('--cnfs', type=str, default="", nargs="+",
                              required=False, help=textwrap.dedent(
            '''\
            Determine the CNF list to generate SSL certificates.
            if without it, would generate certificates for all CNFs. 
            example:--cnfs sc ccsm
            \n'''))

    inner_parser.add_argument('-l', '--list', action="store_true",
                              required=False, help=textwrap.dedent(
            '''\
            Show the applicable lab list for generating SSL certificates.
            with -e, show the applicable CNF list in the specific lab.
            \n'''))

    inner_parser.add_argument('--ca-cert', type=str, default="lab/certs/RootCA/ca.crt",
                              required=False, help=textwrap.dedent(
            '''\
            The CA certificate file path for generating certificates,
            default location: gerrit:5gc_sa_pkg/lab/certs/RootCA/ca.crt,
            it\'s not needed if the working dir is gerrit:5gc_sa_pkg
            \n'''))

    inner_parser.add_argument('--ca-key', type=str, default="lab/certs/RootCA/ca.key",
                              required=False, help=textwrap.dedent(
            '''\
            The CA key file path for generating certificates, 
            default location: gerrit:5gc_sa_pkg/lab/certs/RootCA/ca.key,
            it\'s not needed if the working dir is gerrit:5gc_sa_pkg
            \n'''))

    inner_parser.add_argument('--cert-source', type=str, default="lab/scripts/k8s/ssl_cert_generation/fivegcCertInfo.yml",
                              required=False, help=textwrap.dedent(
            '''\
            The source data file path for generating certificate files,
            default location: gerrit:5gc_sa_pkg/lab/scripts/k8s/ssl_cert_generation/fivegcCertInfo.yml,
            it\'s not needed if the working dir is gerrit:5gc_sa_pkg
            \n'''))

    inner_parser.add_argument('--certs-dir', type=str, default="./fivegc_cert", help=textwrap.dedent(
        '''\
        The directory for saving the generated certificate files,
        if without it,would save certificates in the current directory
        '''))

    return inner_parser


if __name__ == '__main__':

    parser = build_arguments()
    args = parser.parse_args()

    print("INFO: The CA certificate for generating certificates:%s" % os.path.abspath(args.ca_cert))

    ssl_gen = SSLCertificateGenerator(key_dir=os.path.expanduser(args.certs_dir),
                                      ca_cert_path=os.path.expanduser(args.ca_cert),
                                      ca_key_path=os.path.expanduser(args.ca_key))

    cert_source_data = read_cert_data_from_yaml(os.path.expanduser(args.cert_source))
    ssl_gen.country = cert_source_data["country"]
    ssl_gen.state = cert_source_data["state"]
    ssl_gen.localityName = cert_source_data["localityName"]
    ssl_gen.passphrase = cert_source_data["p12_password"].encode()
    list_provided_info_from_cert_source(cert_source_data, parser)

    chosen_lab = {}
    if args.cluster:
        if args.cluster in cert_source_data["lab"].keys():
            chosen_lab[args.cluster] = cert_source_data["lab"][args.cluster]

        else:
            print("Error: wrong input value:%s for argument -e, please choose one from the list:%s" % (
                args.cluster, list(cert_source_data["lab"].keys())))
            sys.exit(1)
    else:
        print("INFO: As argument '-e' is not provided , would generate certificate for "
              "all the labs in the cert source data file")
        chosen_lab = cert_source_data["lab"]

    ssl_gen.gen_certs_from_data_source(chosen_lab, cnfs=args.cnfs)
    ssl_gen.gen_ca()
