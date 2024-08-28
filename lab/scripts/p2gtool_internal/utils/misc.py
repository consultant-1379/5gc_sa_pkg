import logging
import sys
import socket


log = logging.getLogger(__name__)


def setup_logging(level, fmt=None, datefmt=None):
    """Setup debug to console
    :param level: debug level to use.
    :param fmt: format string to use.
    :param datefmt: date format string to use.
    :return: None
    """
    logger = logging.getLogger()
    logger.setLevel(level)
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(
        logging.Formatter('%(levelname)-8s > %(asctime)s : %(message)s',
                          '%Y-%m-%d %H:%M:%S')
    )
    logger.addHandler(ch)


def is_port_open(host, port, timeout=3):
   s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
   s.settimeout(timeout)
   try:
      s.connect((host, int(port)))
      s.shutdown(2)
      return True
   except:
      return False
