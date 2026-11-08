# Chaquopy's `java` module, without Java.
from _lumen_java import JavaStub


class _ProxyBase(object):
    pass


def dynamic_proxy(*interfaces):
    return _ProxyBase


def static_proxy(*args, **kwargs):
    return _ProxyBase


def jclass(name):
    return JavaStub(str(name))


def jarray(element_type):
    def make(values=None):
        if values is None:
            return []
        if isinstance(values, int):
            return [None] * values
        return list(values)
    return make


def cast(cls, obj):
    return obj


def jint(value):
    return int(value)


def jlong(value):
    return int(value)


def jshort(value):
    return int(value)


def jbyte(value):
    return int(value)


def jfloat(value):
    return float(value)


def jdouble(value):
    return float(value)


def jboolean(value):
    return bool(value)


def jchar(value):
    return str(value)


def jvoid(*args):
    return None


def Override(fn):
    return fn


def method(*args, **kwargs):
    def wrap(fn):
        return fn
    return wrap


def constructor(*args, **kwargs):
    def wrap(fn):
        return fn
    return wrap


def detach():
    pass
