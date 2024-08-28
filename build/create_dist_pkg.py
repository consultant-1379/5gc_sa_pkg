#!/usr/bin/env python

import os
import sys
import subprocess
import shutil
import tempfile
import getpass
import tarfile
import logging
import argparse
import configparser
import hashlib
import json


def cfg_parser(cfg_dict):
    log = logging.getLogger('cfg_parser')
    new_cfg_dict = {'build': cfg_dict['build']}
    git_src_dir = {'git_src_dir': {}}
    for x in cfg_dict['build']['git_src_dir'].split(','):
        k = x.split(':')[0].strip()
        v = x.split(':')[1].strip()
        if k == 'nf':
            git_src_dir['git_src_dir'][k] = v
        if k == 'net':
            git_src_dir['git_src_dir'][k] = v
    new_cfg_dict['build'].update(git_src_dir)

    new_cfg_dict['site'] = {
        'site1': {},
        'site2': {}
    }
    for s in new_cfg_dict['site'].keys():
        site_cfg = {
            'pod': cfg_dict[s]['pod'],
            'cluster': [
                {
                    'type': k,
                    'name': v,
                    'cfg_path':
                     os.path.join(git_src_dir['git_src_dir']['nf'],
                     cfg_dict[s]['pod'],
                     v)
                }
                for k, v in cfg_dict[s].items() if '_cluster' in k
            ]
        }
        new_cfg_dict['site'][s] = site_cfg
        if cfg_dict[s].get('sapc'):
            new_cfg_dict['site'][s].update(
                {
                    'sapc': os.path.join(
                        git_src_dir['git_src_dir']['nf'],
                        cfg_dict[s]['pod'],
                        'sapc'
                    )
                }
            )
    log.debug('Parser cfg dict: {0}'.format(str(new_cfg_dict)))
    if new_cfg_dict['build'].get('git_commit') and \
        not new_cfg_dict['build'].get('release_version'):
        log.error("'release_version' is MUST be specified when a specific "
                  "commit is specified")
        return
    return new_cfg_dict


def get_latest_commit_id():
    """get current local latest commit num which has been pushed to remote"""
    return subprocess.check_output(
               args=['git', 'log', '-1', '--pretty=format:%h']
           ).decode()


def list_files(startpath):
    for root, dirs, files in os.walk(startpath):
        dir_content = []
        for dir in dirs:
            go_inside = os.path.join(startpath, dir)
            dir_content.append(list_files(go_inside))
        files_lst = []
        for f in files:
            files_lst.append(f)
        return {'name': root, 'files': files_lst, 'dirs': dir_content}


def collect_files_not_dist(repo_src, cfg_conf):
    log = logging.getLogger('collect_files_not_dist')
    fnd = []
    fnd_cf = '.files_not_distributed'
    cluster_paths = []
    for s in cfg_conf['site'].keys():
        for c in cfg_conf['site'][s]['cluster']:
            cluster_paths.append(os.path.join(repo_src, c['cfg_path']))
        sapc_dir = cfg_conf['site'][s].get('sapc')
        if sapc_dir:
            fnd_dir = os.path.join(repo_src, sapc_dir)
            fnd_file = os.path.join(fnd_dir, fnd_cf)
            if os.path.exists(fnd_file):
                fnd.append(fnd_file)
                with open(fnd_file, 'r', encoding='UTF-8') as f:
                    while line := f.readline().rstrip():
                        fnd.append(os.path.join(fnd_dir, line))

    for cluster_path in cluster_paths:
        cfg_obj_dir = [x for x in os.listdir(cluster_path)]
        for cop in cfg_obj_dir:
            fnd_dir = os.path.join(cluster_path, cop)
            fnd_file = os.path.join(fnd_dir, fnd_cf)
            if os.path.exists(fnd_file):
                fnd.append(fnd_file)
                with open(fnd_file, 'r', encoding='UTF-8') as f:
                    while line := f.readline().rstrip():
                        fnd.append(os.path.join(fnd_dir, line))

    log.debug('Files list which not distributed:\n{0}'.format('\n'.join(fnd)))
    return fnd


def run_tests(repodir):
    log = logging.getLogger("run_tests")
    # move to the git repo dir
    cwd = os.getcwd()
    os.chdir(repodir)
    pytest_cmd = ['/lab/pccc_utils/scripts/gitpush', '--pytest-only']
    try:
        subprocess.check_call(pytest_cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT)
    except:
        log.error(f"Running pytest failed by command {pytest_cmd}")
        return False
    log.info("Running pytest done without issue")
    # move back to previous dir
    os.chdir(cwd)
    return True


def init_repo(repo_url, tmp_dir, branch, commit):
    """Clone a git repo from gerrit into the repo_dir"""
    log = logging.getLogger("clone_repo")

    cmd = "git clone {url} {dir}".format(url=repo_url, dir=tmp_dir)
    log.info("Cloning the repo using cmd: '{0}' ..".format(cmd))
    with open(os.devnull, 'w') as DEVNULL:
        subprocess.check_call(cmd, stderr=DEVNULL, shell=True)

    # move to the git repo dir
    cwd = os.getcwd()
    os.chdir(tmp_dir)

    # checkout the commit, if specified
    if commit is not None:
        cmd = "git checkout {0}".format(commit)
        log.info("Checkout commit '{0}' using: {1}".format(commit, cmd))
        with open(os.devnull, 'w') as DEVNULL:
            subprocess.check_call(cmd, stderr=DEVNULL, shell=True)

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
                subprocess.check_call(cmd, stderr=DEVNULL, shell=True)
    git_commit_id = get_latest_commit_id()
    log.debug('GIT commit id is {0}'.format(git_commit_id))
    log.debug("GIT branch name is {0}".format(branch))

    # move back to previous dir
    os.chdir(cwd)

    return git_commit_id


def cleanup(git_repo_dir):
    """Remove the repo dir"""
    log = logging.getLogger("cleanup")
    try:
        log.debug("Deleting {0} ..".format(git_repo_dir))
        shutil.rmtree(git_repo_dir, onerror=onerror)
    except OSError as exp:
        log.error("Cleanup failed: {0}".format(exp))


def make_tarfile(output_filename, *source_files):
    log = logging.getLogger("make_tarfile")
    log.info("Creating the tarball")
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


def setup_logging(level):
    log_fmt = '%(levelname)-8s > %(message)s'
    logger = logging.getLogger()
    logger.setLevel(level)
    formatter = logging.Formatter(log_fmt, datefmt='%Y-%m-%d %H:%M:%S')
    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    logger.addHandler(handler)


def onerror(func, path, exc_info):
    """
    Error handler for ``shutil.rmtree``.

    If the error is due to an access error (read only file)
    it attempts to add write permission and then retries.
    If the error is for another reason it re-raises the error.

    Usage : ``shutil.rmtree(path, onerror=onerror)``
    """
    import stat
    # pylint: disable=misplaced-bare-raise
    if not os.access(path, os.W_OK):
        # Is the error an access error ?
        os.chmod(path, stat.S_IWUSR)
        func(path)
    else:
        raise


def main(input_args):
    log = logging.getLogger(__name__)

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-c", "--config",
        dest="build_cfg",
        help="the build_rel.cfg path to be used to generate a package dist",
        required=True,
        metavar="FILE")

    parser.add_argument(
        "--branch",
        dest="git_branch",
        help="the git branch to use (this field should be used "
             "mainly by Jenkins)",
        required=False,
        metavar="BRANCH")

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

    log.debug("Input arguments: {0}".format(options))

    log.debug("Parsing the config file")
    cfg = configparser.ConfigParser()

    # create a tmp dir to fetch and store the git repo
    repo_dir = tempfile.mkdtemp()
    try:
        # read the config file
        cfg.read(options.build_cfg)
        cfg_conf = cfg_parser(cfg.__dict__.get('_sections'))
    except BaseException as mexp:
        parser.error("Could not parse the build_rel.cfg: {0}: {1}"
                     .format(mexp.__class__.__name__, mexp))
    else:

        # the user running the script
        curr_user = getpass.getuser()

        # clone the sp repo
        gerrit_url = cfg_conf['build']['git_repo'].format(user=curr_user)

        # src dirs
        nf_src_dir = cfg_conf['build']['git_src_dir']['nf']
        net_src_dir = cfg_conf['build']['git_src_dir']['net']

        # use the specific commit if it was specified in the config
        git_commit = None
        git_branch = options.git_branch
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
        elif cfg_conf['build'].get('git_commit'):
            git_commit = cfg.get('build', 'git_commit')
            rels_ver = cfg.get('build', 'release_version')
        elif cfg_conf['build'].get('git_branch'):
            log.debug("Using the GIT branch specified via the config file")
            git_branch = cfg_conf['build'].get('git_branch')
        else:
            parser.error("'git_branch' must be specified if "
                         "'git_commit' is missing")

        git_commit_id = init_repo(
            repo_url=gerrit_url,
            tmp_dir=repo_dir,
            branch=git_branch,
            commit=git_commit)

        # run pytest
        if run_tests(repo_dir) is not True:
            raise Exception("Running test case with error, STOPPED!!!")

        # collect all files to a list which will NOT be distributed
        do_not_include = collect_files_not_dist(repo_dir, cfg_conf)

        # remove all files and folders in the 'do_not_include' list
        for entry_path in do_not_include:
            if os.path.exists(entry_path):
                if os.path.isdir(entry_path):
                    log.debug("Removing dir '{0}'".format(entry_path))
                    shutil.rmtree(entry_path)
                else:
                    log.debug("Removing file '{0}'".format(entry_path))
                    os.remove(entry_path)
                    entry_path_dir = \
                        os.path.dirname(os.path.realpath(entry_path))
                    if not any(os.scandir(entry_path_dir)):
                        log.warning(
                            'Removing empty dir {0} that file {1} '
                            'belongs to'.format(entry_path_dir, entry_path)
                        )
                        shutil.rmtree(entry_path_dir)
            else:
                log.debug("File '{0}' does not exist".format(entry_path))

        # define/create sp pkg dist directory structure
        sp_dir = '5gc_sa_pkg'
        sp_pack_dir = 'dm5gc_on_nfvi_{0}_sp_{1}'.format(rels_ver, git_commit_id)
        config_dir = os.path.join(repo_dir, sp_dir, 'config')
        os.mkdir(os.path.join(repo_dir, sp_dir))
        os.mkdir(os.path.join(repo_dir, sp_pack_dir))
        os.mkdir(config_dir)

        # copy version.txt
        shutil.copy(os.path.join(repo_dir, nf_src_dir, 'version.txt'),
                    config_dir)

        # copy net hot files
        shutil.copytree(os.path.join(repo_dir, net_src_dir),
                        os.path.join(repo_dir, sp_dir, net_src_dir))

        # copy site nf files
        for s in cfg_conf['site'].keys():
            site_dir = os.path.join(config_dir, s)
            os.mkdir(site_dir)
            for c in cfg_conf['site'][s]['cluster']:
                src = os.path.join(repo_dir, c['cfg_path'])
                dest = os.path.join(site_dir, c['type'])
                shutil.copytree(src, dest)
            sapc_dir = cfg_conf['site'][s].get('sapc')
            if sapc_dir:
                src = os.path.join(repo_dir, sapc_dir)
                dest = os.path.join(site_dir, 'sapc')
                shutil.copytree(src, dest)

        # define list files shell command
        list_files_cmd = 'tree'
        if shutil.which(list_files_cmd):
            log.info("Printout SP files by 'tree' command:\n{0}".format(
               subprocess.check_output(
                   ['tree', os.path.join(repo_dir, sp_dir)]).decode()))
        else:
            log.warning("Can NOT printout SP files Due to Shell "
                        "command {0} not found".format(list_files_cmd))
            log.info("Printout SP files:\n{0}".format(
                json.dumps(
                    list_files(os.path.join(repo_dir, sp_dir)), indent=4)))
        sp_pkg_name = "5gc_sa_pkg.tar.gz"
        sp_pkg_checksum_name = "{0}.sha256".format(sp_pkg_name)
        sp_pack_name = "{0}.tar.gz".format(sp_pack_dir)

        make_tarfile(os.path.join(repo_dir, sp_pkg_name),
                     os.path.join(repo_dir, sp_dir))
        log.info("Generated SP pkg file: {0}".format(
            os.path.join(repo_dir, sp_pkg_name)))
        with open(os.path.join(repo_dir, sp_pkg_checksum_name), 'w') as f:
            f.write(sha256sum(os.path.join(repo_dir, sp_pkg_name)))
        log.info("Generated SP pkg checksum file: {0}".format(
            os.path.join(repo_dir, sp_pkg_checksum_name)))
        # copy SP Package to SP pack Directory
        shutil.copy(os.path.join(repo_dir, sp_pkg_name),
                    os.path.join(repo_dir, sp_pack_dir))
        log.debug("Copied SP pkg file {0} to pack dir {1}".format(
            os.path.join(repo_dir, sp_pkg_name),
            os.path.join(repo_dir, sp_pack_dir)))
        shutil.copy(os.path.join(repo_dir, sp_pkg_checksum_name),
                    os.path.join(repo_dir, sp_pack_dir))
        log.debug("Copied SP pkg checksum file {0} to pack dir {1}".format(
            os.path.join(repo_dir, sp_pkg_checksum_name),
                    os.path.join(repo_dir, sp_pack_dir)))
        make_tarfile(sp_pack_name,
                     os.path.join(repo_dir, sp_pack_dir))
        log.info("Generated final SP pack file: {0}".format(sp_pack_name))

    finally:
        # cleanup
        cleanup(repo_dir)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
