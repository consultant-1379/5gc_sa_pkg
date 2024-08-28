import unittest
import json
import json5
import yaml
import os
import re


class TestValidateFileSyntax(unittest.TestCase):
    """
    """
    def setUp(self):
        self.validated_files = []

    #@unittest.skip("skipping")
    def test_validate_network_hot_file(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = '5gc_sa_net_hot'
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path)

    #@unittest.skip("skipping")
    def test_validate_installation_config_file_n28(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = 'lab/n28'
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path)

    def test_validate_installation_config_file_n99(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = 'lab/n99'
        excluded_dirs=['cee']
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path,
                          excluded_dirs=excluded_dirs)

    @unittest.skip("skipping")
    def test_validate_installation_config_file_n87(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = 'lab/n87'
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path)

    def test_validate_installation_config_file_n280(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = 'lab/n280'
        excluded_dirs=['cee']
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path,
                          excluded_dirs=excluded_dirs)

    def test_validate_upgrade_config_file_upgrade(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = ['upgrade-1.9-1.10']
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path)

    def test_validate_pod56_file(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = 'lab/pod56'
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path,
                          excluded_dirs=['cee10'])

    def test_validate_build_config_file(self):
        ftypes = ['yaml', 'yml', 'json', 'json5', 'cfg']
        dir_path = 'build'
        for ftype in ftypes:
            self.run_test(ftype,
                          dir_path)

    def validate_file_syntax(self, ftype, filepath):
        if ftype in ['yaml', 'yml']:
            with open(filepath, encoding="utf8") as data_file:
                content = data_file.read()
            yaml_data = yaml.load(content, Loader=yaml.FullLoader)
            return True
        elif ftype in ['json']:
            with open(filepath, encoding="utf8") as data_file:
                json_data = json.load(data_file)
            return True
        elif ftype in ['json5']:
            with open(filepath, encoding="utf8") as data_file:
                json5_data = json5.load(data_file)
            return True
        elif ftype in ['cfg', 'ini']:
            import configparser
            cfg = configparser.ConfigParser()
            cfg.read(filepath)
            return True
        else:
            raise Exception("{0} type file not supported.".format(ftype))

    def run_test(self, ftype, dir_path, excluded_dirs=None):
        m = re.compile(r"^.*\.{0}$".format(ftype))
        if isinstance(dir_path, str):
            for root, directories, filenames in os.walk(dir_path):
                cdir = root.lstrip(dir_path)
                for filename in filenames:
                    if m.match(filename):
                        if excluded_dirs and \
                           any([True for d in excluded_dirs if d in cdir]):
                            continue
                        filepath = os.path.join(root, filename)
                        self.validate_file_syntax(ftype, filepath)
        if isinstance(dir_path, list):
            for dp in dir_path:
                self.run_test(ftype, dp, excluded_dirs)


if __name__ == '__main__':
    unittest.main()
