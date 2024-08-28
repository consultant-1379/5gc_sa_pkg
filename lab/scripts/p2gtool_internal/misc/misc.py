import logging
import sys


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
