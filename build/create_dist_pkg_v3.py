#!/usr/bin/env python3

import json
import os
import sys
import logging
import yaml
import tempfile
import shutil
import argparse
import hashlib
import tarfile
import subprocess
import getpass
import errno
import glob
import string
from gen_markdown_table import gen_markdown_table
from jinja2 import Environment, FileSystemLoader
from prettytable import PrettyTable


def make_tarfile(output_filename, *source_files):
    log = logging.getLogger("make_tarfile")
    log.info(f"Creating the tarball {output_filename}")
    with tarfile.open(output_filename,
                      "w:gz",
                      format=tarfile.GNU_FORMAT) as tar:
        for sf in source_files:
            tar.add(sf,
                    arcname=os.path.basename(sf),
                    filter=reset)


def sha256sum(filename):
    sha256_hash = hashlib.sha256()
    with open(filename, "rb") as f:
        # Read and update hash string value in blocks of 4K
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def reset(tarinfo):
    tarinfo.uid = tarinfo.gid = 0
    tarinfo.uname = tarinfo.gname = "root"
    return tarinfo


def get_latest_commit_id(repo_dir):
    """get current local latest commit num which has been pushed to remote"""
    return subprocess.check_output(
        args=['git', 'log', '-1', '--pretty=format:%h'], cwd=repo_dir).decode()


def run_tests(repodir):
    log = logging.getLogger("run_tests")
    # move to the git repo dir
    cwd = os.getcwd()
    os.chdir(repodir)
    pytest_cmd = ['/lab/pccc_utils/scripts/gitpush', '--pytest-only']
    log.info("Running test cases via pytest ...")
    try:
        subprocess.check_call(pytest_cmd,
                              stdout=subprocess.DEVNULL,
                              stderr=subprocess.STDOUT)
    except:
        log.error(f"Running pytest failed by command {pytest_cmd}")
        return False
    log.info("All test cases are completed without issue")
    # move back to previous dir
    os.chdir(cwd)
    return True


def init_repo(repo_url, repo_dir, branch, commit=None):
    """Clone a git repo from gerrit into the repo_dir"""
    log = logging.getLogger("init_repo")

    cmd = "git clone {url} {dir}".format(url=repo_url, dir=repo_dir)
    log.info("Cloning the repo using cmd: '{0}' ..".format(cmd))
    with open(os.devnull, 'w') as DEVNULL:
        subprocess.check_call(cmd, stderr=DEVNULL, shell=True)

    # checkout the commit, if specified
    if commit is not None:
        cmd = "git checkout {0}".format(commit)
        log.info("Checkout commit '{0}' using: {1}".format(commit, cmd))
        with open(os.devnull, 'w') as DEVNULL:
            subprocess.check_call(cmd, stderr=DEVNULL, shell=True, cwd=repo_dir)

    # checkout the branch if not master (master is the default branch)
    else:
        assert branch is not None
        if branch != 'master':
            # the branch name can contain /remotes/origin as prefix or not
            # if it does not contain it, add it here
            # as it's needed when running git checkout
            if not branch.startswith('remotes/origin/'):
                branch = "remotes/origin/{0}".format(branch)

            cmd = "git checkout --track {0}".format(branch)
            log.info("Checkout branch '{0}' using: {1}".format(branch, cmd))
            with open(os.devnull, 'w') as DEVNULL:
                subprocess.check_call(cmd, stderr=DEVNULL, shell=True, cwd=repo_dir)
    git_commit_id = get_latest_commit_id(repo_dir)
    log.debug('GIT commit id is {0}'.format(git_commit_id))
    log.debug("GIT branch name is {0}".format(branch))

    return git_commit_id


def cfg_parser(cfgfile):
    """
    :param cfgfile: config file path
    :return:
    """
    with open(cfgfile, 'r') as f:
        content = f.read()

    return yaml.load(content, Loader=yaml.FullLoader)


def gen_usecases_data(data, usecases):

    def _gen_site_config(obj, obj_type, uc_data):
        for d in obj:
            for k, v in d.items():
                for cfg in v:
                    _tags = cfg.get('tags', [])
                    _tags = usecases if 'all' in _tags \
                        else _tags
                    if uc not in _tags:
                        continue
                    obj_config = {
                        'include_files': cfg.get('include_files', '*'),
                        'config_path': cfg['config_path'],
                        'type': k.rstrip(string.digits),
                        'id': k,
                        'tags': _tags
                    }
                    if obj_type == 'infra':
                        cdp = (k, [])
                    elif obj_type == 'sapc':
                        cdp = ('sapc', [])
                    else:
                        cdp = (cfg['cluster'], {})

                    site_data = uc_data.setdefault(cfg['site'], {})
                    cluster_data = site_data.setdefault(*cdp)
                    if obj_type == 'infra':
                        if obj_config not in cluster_data:
                            cluster_data.append(obj_config)
                    elif obj_type == 'sapc':
                        if obj_config not in cluster_data:
                            cluster_data.append(obj_config)
                    else:
                        obj_data = cluster_data.setdefault(obj_type, [])
                        if obj_config not in obj_data:
                            obj_data.append(obj_config)
    ucs_list = []
    for uc in usecases:
        uc_data = {'name': uc}
        ucs_list.append(uc_data)
        _gen_site_config(data['caas'], 'caas', uc_data)
        _gen_site_config(data['cnfs'], 'cnfs', uc_data)
        if 'infra' in data:
            _gen_site_config(data['infra'], 'infra', uc_data)
        if 'sapc' in data:
            _gen_site_config([{'sapc': data['sapc']}], 'sapc', uc_data)
    print(yaml.dump(ucs_list, indent=2))
    return ucs_list


def gen_package_data(input_data, pkg_name=''):
    """
    """
    log = logging.getLogger("gen_package_data")
    templ_dir = os.path.join(os.path.dirname(__file__), 'templates')
    jinja = Environment(
        loader=FileSystemLoader(templ_dir),
        trim_blocks=True,
        lstrip_blocks=True)
    log.debug(f"Template directory is {templ_dir}")
    template = jinja.get_template('release_package_structure_v3.yaml.j2')

    usecases = gen_usecases_data(input_data, input_data['usecases'])

    output_data = yaml.load(
        template.render(usecases=usecases,
                        pkg_name=pkg_name or input_data['pkg_name']),
        Loader=yaml.FullLoader)
    return output_data


def gen_directory_path(directory_data, parent=""):
    log = logging.getLogger("gen_directory_path")
    directories = []

    def _gen_directory_path(directory_data=directory_data, parent=parent):
        assert isinstance(directory_data, list)
        for d in directory_data:
            [(k, v)] = d.items()
            if v is None:
                log.warning("Nothing in directory {0}/{1}".format(parent, k))
                continue
            for obj in v:
                if "config_path" in obj:
                    obj_id = obj.get("id", obj["type"])
                    if obj["type"] in ["eccd", "sapc", "dcgw", "dns"]:
                        target_dir = os.path.join(parent, k)
                    else:
                        target_dir = os.path.join(parent, k, obj_id)
                    includes_files = obj.get("include_files", [])
                    # it is upgrade configuration when includes_files is dict type
                    if isinstance(includes_files, dict):
                        upgrade_base_dir = obj["tags"][0]
                        base_dir = os.path.join("lab", upgrade_base_dir, obj["config_path"])
                        base_ver = upgrade_base_dir.split('-')[1]
                        base_target_dir = os.path.join(target_dir, f"ts{base_ver}-config")
                        directories.extend([
                            (obj_id, base_target_dir, base_dir, includes_files["base"]),
                            (obj_id, target_dir, base_dir, includes_files["upgrade"])]
                        )
                    else:
                        directories.append((obj_id, target_dir, obj["config_path"], includes_files))
                else:
                    tparent = os.path.join(parent, k)
                    _gen_directory_path([obj], tparent)
    _gen_directory_path()
    return directories


def gen_versions(data):
    verTable = PrettyTable(["Product", "Version"])

    verTable.align['Product'] = 'l'
    verTable.align['Version'] = 'l'

    # Add rows
    for nf, ver in data["versions"].items():
        verTable.add_row([nf.upper(), ver])

    return str(verTable)


def gen_readme_file(data, tree_structure, readme_template, readme_target_file, target_version):
    with open(readme_template, 'r') as read_stream:
        content = read_stream.read()
    new_content = content.replace('$TRACK', data["track"])
    new_content = new_content.replace('$TARGET_VERSION', target_version)
    #new_content = new_content.replace('$VERSIONS', gen_versions(data))
    new_content = new_content.replace('$STRUCTURE', tree_structure)
    with open(readme_target_file, 'w') as write_stream:
        write_stream.write(new_content)


def file_filter(fpps):
    """
    :param fpps: list of file path patterns,
    support Unix shell-style wildcards
    :return: list
    """
    log = logging.getLogger('file_filter')
    flist = []
    for fpp in fpps:
        matched_fpp = glob.glob(fpp)
        if matched_fpp:
            flist.extend(glob.glob(fpp))
        else:
            log.error(f"File {fpp} does not exist in remote GERRIT repo!")
    return flist


def find_empty_dirs(root_dir='.'):
    """find empty directories"""
    for dirpath, dirs, files in os.walk(root_dir):
        if not dirs and not files:
            yield dirpath


def find_empty_files(root_dir='.'):
    """find empty files"""
    for root, dirs, files in os.walk(root_dir):
        for name in files:
            filepath = os.path.join(root, name)
            if os.stat(filepath).st_size == 0:
                yield filepath


def find_matched_files(root_dir, file_patter):
    for root, dirs, files in os.walk(root_dir, file_patter):
        for name in files:
            if name == file_patter or file_patter in os.path.join(root, name):
                yield os.path.join(root, name)
        for name in dirs:
            if name == file_patter or file_patter in os.path.join(root, name):
                yield os.path.join(root, name)


def _remove_file(file_path):
    log = logging.getLogger('_remove_file')
    if os.path.exists(file_path):
        if os.path.isdir(file_path):
            log.debug("Removing dir '{0}'".format(file_path))
            shutil.rmtree(file_path)
        else:
            log.debug("Removing file '{0}'".format(file_path))
            os.remove(file_path)


def _copy_file(filelist, dest):
    log = logging.getLogger('_copy_file')
    copied = True
    for file in filelist:
        if os.path.isdir(file):
            dest_dname = os.path.join(dest, os.path.basename(file))
            log.debug(f"Copy directory from {file} to {dest_dname}")
            shutil.copytree(file, dest_dname)
        elif os.path.isfile(file):
            log.debug(f"Copy file from {file} to {dest}")
            shutil.copy2(file, dest)
        else:
            copied = False
            log.error(f"Source path {file} does not exist")
    return copied


def _get_next_letter(letter):
    from itertools import product

    def get_alphaseqs(alphabet):
        """ get first n alphaseq """
        for l in range(1, len(alphabet) + 1):
            for p in product(alphabet, repeat=l):
                yield ''.join(p)
    alphabet = 'abcdefghijklmnopqrstuvwxyz'
    letter_seqs = get_alphaseqs(alphabet)
    for i in letter_seqs:
        if i == letter:
            return letter_seqs.__next__()


def build_release_pkg(oridata, repodir, basedir, version, commit_id, push_tag=True, predelivery=False, out_dir=None):
    log = logging.getLogger('build_release_pkg')
    cwd = os.getcwd()
    sp_commit_id, tsconfig_commit_id = commit_id
    pkg_name = f"dm-5gc-{version}-on-ericsson-nfvi-support-package"
    if predelivery:
        pkg_name += '_predelivery'
    pkg_fullname = '{0}.tgz'.format(pkg_name)
    pkg_checksum_fullname = '{0}.sha256'.format(pkg_fullname)
    data = gen_package_data(oridata, pkg_name)
    # switch to base tmp directory
    os.chdir(basedir)
    log.debug(json.dumps(gen_directory_path(data["package"]["content"]), indent=4))
    rootdir = list(data["package"]["content"][0].keys())[0]

    file_paths = gen_directory_path(data["package"]["content"], parent='')
    for obj_id, rp, lp, files in file_paths:
        # obj_id: nf id, rp: release path, lp: GIT repo lab path
        lp = os.path.join(repodir, lp)
        include_files = file_filter([os.path.join(lp, f) for f in files]) \
            if files else [os.path.join(lp, f) for f in os.listdir(lp)] if os.path.isdir(lp) else [lp]
        # remove files not distributed
        fnd = os.path.join(lp, data["package"]["fnd"])
        exclude_files = [fnd]
        if os.path.exists(fnd):
            with open(fnd, 'r', encoding='UTF-8') as f:
                while line := f.readline().rstrip():
                    exclude_files.append(os.path.join(lp, line).rstrip('/'))
                    _remove_file(os.path.join(lp, line))
            _remove_file(fnd)
        if not os.path.exists(rp):
            log.info(f"Create release path {rp}")
            rpdir = os.path.dirname(rp) if os.path.isfile(lp) else rp
            os.makedirs(rpdir)
        source_files = list(set(include_files) - set(exclude_files))
        if not _copy_file(source_files, rp):
            raise FileNotFoundError(
                errno.ENOENT, os.strerror(errno.ENOENT), lp)

    # tree structure of support package
    sp_tree = subprocess.check_output(['tree', pkg_name]).decode()

    # generate readme.txt
    readme_template = os.path.join(repodir, "build/templates/readme.txt")
    gen_readme_file(oridata, sp_tree, readme_template,
                    os.path.join(pkg_name, "readme.txt"),
                    version)

    # switch to current working directory
    os.chdir(cwd)

    # switch to out direcotry and compress outer directory
    if out_dir:
        os.chdir(out_dir)
    make_tarfile(pkg_fullname,
                 os.path.join(basedir, pkg_name))
    chksum = sha256sum(pkg_fullname)
    log.info("Generated dual-mode 5gc on nfvi SP tar file: {0} with commit id {1}".format(pkg_fullname, sp_commit_id))
    log.info("The sha256 checksum for {0} is {1}\n".format(pkg_fullname, chksum))

    if push_tag:
        # push tag
        tag_name = f"sp-pre-{version}" if predelivery else f"sp-{version}"
        existed_reltag = subprocess.check_output(
            f"git tag -l '{tag_name}*' --sort=creatordate | tail -1",
            shell=True).decode().strip()
        next_subv = 'a'
        if existed_reltag:
            subv = existed_reltag.split('-')[-1].replace(version, '')
            next_subv = _get_next_letter(subv)
        # switch to repodir to push tag
        os.chdir(repodir)
        git_tag_cmd = f'git tag -a {tag_name}{next_subv} {sp_commit_id} ' \
                      f'-m "Release TS DM 5GC {version} on NFVI support ' \
                      f'package whose checksum is {chksum} with ts-config commit {tsconfig_commit_id}"'
        subprocess.check_call(git_tag_cmd, shell=True)
        log.info(f"Tagged commit {sp_commit_id} with {tag_name}{next_subv} for {version}")
        subprocess.check_call('git push --tags', shell=True)
        log.info(f"Pushed tag {tag_name}{next_subv} to remote for commit {sp_commit_id}")
        # print support package info to be added to eridoc
        sp_pkg_info = "sha256 checksum: {0}\ncommit id: {1}\ntag: {2}".format(chksum, sp_commit_id, f'{tag_name}{next_subv}')
        log.info(f"Copy the following content to SP description field in genernal info in eridoc:\n{sp_pkg_info}")

        # switch back to previous working directory
        os.chdir(cwd)


def setup_logging(level):
    log_fmt = '%(levelname)-8s > %(message)s'
    logger = logging.getLogger()
    logger.setLevel(level)
    formatter = logging.Formatter(log_fmt, datefmt='%Y-%m-%d %H:%M:%S')
    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    logger.addHandler(handler)


def main(input_args):
    log = logging.getLogger(__name__)

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-c", "--config",
        dest="build_cfg",
        help="the build_rel confi file path to be used to generate a package dist",
        default="build/build_rel.yaml",
        metavar="FILE")

    parser.add_argument(
        "--local",
        action="store_true",
        dest="use_local_cfg",
        default=False,
        help="use local build release config file")

    parser.add_argument(
        "--predelivery",
        action="store_true",
        dest="is_predelivery",
        default=False,
        help="SP pkg name will be tagged with predelivery suffix")

    parser.add_argument(
        "--branch",
        dest="git_branch",
        help="the git branch to use (this field should be used "
             "mainly by Jenkins)",
        required=True,
        metavar="BRANCH")

    parser.add_argument(
        "--no-pytest",
        action="store_true",
        dest="no_pytest",
        default=False,
        help="Don't run pytest")

    parser.add_argument(
        "--no-tag",
        action="store_true",
        dest="no_push_tag",
        default=False,
        help="Don't push tag to remote")

    parser.add_argument(
        '--out-dir',
        dest='out_dir',
        default='.',
        help='output directory for the tar file')

    parser.add_argument(
        "--debug",
        action="store_true",
        dest="verbose",
        default=False,
        help="print more info")

    options = parser.parse_args(input_args)

    # setup logging
    if options.verbose:
        # set logging to debug
        setup_logging(logging.DEBUG)
    else:
        setup_logging(logging.INFO)

    tmpdir = tempfile.TemporaryDirectory()
    repodir = os.path.join(tmpdir.name, "dm_5gc_nfvi_repo")
    repodir_tsconfig = os.path.join(tmpdir.name, "dm_5gc_nfvi_repo_tsconfig")
    data = cfg_parser(options.build_cfg)

    # use the specific commit if it was specified in the config
    git_commit = None
    git_branch = options.git_branch
    git_branch_tsconfig = "dm5gc-" + options.git_branch.split('-')[1] + "-nfvi"
    rels_ver = None
    # A branch can be specified either by CLI or via the config file
    # when a branch is specified by CLI, then branch/commit config
    # in the config file will be ingored.
    # when a branch is not specified by CLI, then either a commit OR
    # a branch must be speicified in the config file, but commit has
    # priority.
    if git_branch is not None:
        log.debug("Using the GIT branch specified via CLI")
        rels_ver = git_branch.split('-')[1]
    elif data['build']['git_commit'] and data['build']['release_version']:
        log.debug("Using the GIT commit id specified via the config file")
        git_commit = data['build']['git_commit']
        rels_ver = data['build']['release_version']
    elif data['build']['git_branch']:
        log.debug("Using the GIT branch specified via the config file")
        git_branch = data['build']['git_branch']
    else:
        parser.error("'git_branch' must be specified if "
                     "'git_commit' is missing")

    git_commit_id = init_repo(
        repo_url=data['build']['git_repo'].format(user=getpass.getuser()),
        repo_dir=repodir,
        branch=git_branch,
        commit=data['build']['git_commit'])

    git_commit_id_tsconfig = ''
    try:
        git_commit_id_tsconfig = init_repo(
            repo_url=data['build']['git_repo_tsconfig'].format(user=getpass.getuser()),
            repo_dir=repodir_tsconfig,
            branch=git_branch_tsconfig)
    except subprocess.CalledProcessError as e:
        log.error("Failed to fetch latest commit id for 'ts-config' repo")

    # update data using remote build_rel.yaml
    if not options.use_local_cfg:
        data = cfg_parser(os.path.join(repodir, 'build/build_rel.yaml'))

    if options.is_predelivery:
        data['pkg_name'] = data['pkg_name'] + '_' + 'predelivery'

    # run pytest
    if options.no_pytest is not True and run_tests(repodir) is not True:
        raise Exception("Running test case with error, STOPPED!!!")

    build_release_pkg(data, repodir, tmpdir.name, rels_ver, commit_id=(git_commit_id, git_commit_id_tsconfig), push_tag=not options.no_push_tag, predelivery=options.is_predelivery, out_dir=options.out_dir)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
