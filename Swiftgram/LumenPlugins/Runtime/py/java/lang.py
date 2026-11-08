# java.lang — threads run their Runnable on the plugin queue, boxed types are plain values.


class Object(object):
    pass


class Runnable(object):
    def run(self):
        pass


class Thread(object):
    def __init__(self, target=None, *args, **kwargs):
        self._target = target

    def start(self):
        import _lumen_host
        target = self._target
        if target is None:
            _lumen_host.defer(self.run, 0)
        else:
            _lumen_host.defer_runnable(target, 0)

    def run(self):
        pass

    def join(self, *args):
        pass

    def interrupt(self):
        pass

    def isAlive(self):
        return False

    def setDaemon(self, value):
        pass

    def setName(self, name):
        pass

    def setPriority(self, value):
        pass

    @staticmethod
    def sleep(millis, *args):
        import time
        time.sleep(float(millis) / 1000.0)

    @staticmethod
    def currentThread():
        return Thread()


class Integer(object):
    MAX_VALUE = 2147483647
    MIN_VALUE = -2147483648

    @staticmethod
    def valueOf(value):
        return int(value)

    @staticmethod
    def parseInt(value, radix=10):
        return int(str(value), radix)

    @staticmethod
    def toString(value):
        return str(value)


class Long(Integer):
    MAX_VALUE = 9223372036854775807
    MIN_VALUE = -9223372036854775808

    @staticmethod
    def parseLong(value, radix=10):
        return int(str(value), radix)


class Float(object):
    @staticmethod
    def valueOf(value):
        return float(value)

    @staticmethod
    def parseFloat(value):
        return float(value)


Double = Float


class Boolean(object):
    TRUE = True
    FALSE = False

    @staticmethod
    def valueOf(value):
        if isinstance(value, str):
            return value.lower() == "true"
        return bool(value)

    @staticmethod
    def parseBoolean(value):
        return str(value).lower() == "true"


class String(object):
    @staticmethod
    def valueOf(value):
        return str(value)

    @staticmethod
    def format(fmt, *args):
        try:
            return str(fmt) % args
        except Exception:
            return str(fmt)


class CharSequence(object):
    pass


class System(object):
    @staticmethod
    def currentTimeMillis():
        import time
        return int(time.time() * 1000)

    @staticmethod
    def nanoTime():
        import time
        return int(time.time() * 1000000000)

    @staticmethod
    def getProperty(key, default=None):
        return default


class Math(object):
    @staticmethod
    def max(a, b):
        return max(a, b)

    @staticmethod
    def min(a, b):
        return min(a, b)

    @staticmethod
    def abs(a):
        return abs(a)

    @staticmethod
    def round(a):
        return int(round(a))


class Exception_(Exception):
    pass


import _lumen_java
_lumen_java.fill_module(__name__)
