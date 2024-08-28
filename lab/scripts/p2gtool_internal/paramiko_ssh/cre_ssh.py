import socket
import paramiko
import time
import logging
import warnings
warnings.filterwarnings(action='ignore',module='.*paramiko.*')


def _check_alive(host, port=22, timeout=3):
    original_timeout = socket.getdefaulttimeout()
    socket.setdefaulttimeout(timeout)
    log = logging.getLogger()
    try:
        transport = paramiko.Transport((host, port))
        transport.close()
        return True
    except:
        log.error("connect to {0} timed out.".format(host))
    finally:
        socket.setdefaulttimeout(original_timeout)
    return False


def cre_ssh(hostname, username, password, command, port=22, timeout=15,
            wait_sec=1):
    if logging.root.level >= logging.INFO:
        logging.getLogger("paramiko").setLevel(logging.CRITICAL)
    outputs = ''
    if _check_alive(hostname, port):
        t = paramiko.Transport((hostname, port))
        try:
            t = paramiko.Transport((hostname, port))
            t.connect(username=username, password=password)
            chan = t.open_session()
            chan.settimeout(timeout)
            chan.get_pty()
            chan.invoke_shell()
            time.sleep(0.5)
            chan.send("{0}\r".format(command))
            time.sleep(wait_sec)
            outputs += chan.recv(65535).decode('ascii')
        except:
            pass 
        finally:
            t.close()
    return outputs
