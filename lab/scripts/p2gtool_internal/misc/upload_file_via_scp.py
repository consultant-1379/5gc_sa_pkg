import subprocess


def upload_file_via_scp(host, src_file, dest_file):
    """upload file to remote host through scp command"""
    if rc == 0:
        cmd = 'scp -p {0} {1}:{2}'.format(src_file, host, dest_file)
        child = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return child.wait()
    return rc
