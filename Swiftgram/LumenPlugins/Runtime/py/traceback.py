# traceback: Skulpt keeps no frames we can walk, so the text is the exception itself.
import sys


def format_exc(*args, **kwargs):
    info = sys.exc_info()
    if info[1] is None:
        return "NoneType: None\n"
    return "Traceback (most recent call last):\n" + type(info[1]).__name__ + ": " + str(info[1]) + "\n"


def print_exc(*args, **kwargs):
    from _lumen_bridge import log
    log(format_exc())


def format_exception(etype, value=None, tb=None, *args, **kwargs):
    if value is None:
        value = etype
    return [type(value).__name__ + ": " + str(value) + "\n"]


def format_exception_only(etype, value=None):
    return format_exception(etype, value)


def print_stack(*args, **kwargs):
    pass


def format_stack(*args, **kwargs):
    return []


def extract_stack(*args, **kwargs):
    return []
