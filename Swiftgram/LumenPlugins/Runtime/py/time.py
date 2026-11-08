# time, backed by the app's clock (Skulpt's own sleep needs suspensions, which hooks
# cannot use).
import _lumen
from _lumen_bridge import native

timezone = 0
altzone = 0
daylight = 0
tzname = ("UTC", "UTC")


class struct_time(tuple):
    def __new__(cls, values):
        return tuple.__new__(cls, values)

    @property
    def tm_year(self):
        return self[0]

    @property
    def tm_mon(self):
        return self[1]

    @property
    def tm_mday(self):
        return self[2]

    @property
    def tm_hour(self):
        return self[3]

    @property
    def tm_min(self):
        return self[4]

    @property
    def tm_sec(self):
        return self[5]

    @property
    def tm_wday(self):
        return self[6]

    @property
    def tm_yday(self):
        return self[7]

    @property
    def tm_isdst(self):
        return self[8]


def time():
    return _lumen.now_ms() / 1000.0


def time_ns():
    return int(_lumen.now_ms() * 1000000)


def monotonic():
    return time()


perf_counter = monotonic
process_time = monotonic


def monotonic_ns():
    return time_ns()


def sleep(seconds):
    native("sleep", seconds=float(seconds))


def _to_seconds(t):
    if t is None:
        return time()
    if isinstance(t, (int, float)):
        return float(t)
    return mktime(t)


def localtime(t=None):
    return struct_time(native("localtime", t=_to_seconds(t)))


def gmtime(t=None):
    return struct_time(native("localtime", t=_to_seconds(t), utc=True))


def mktime(t):
    return float(native("mktime", parts=list(t)[:6]))


def strftime(fmt, t=None):
    return native("strftime", format=str(fmt), t=_to_seconds(t))


def ctime(t=None):
    return strftime("%a %b %d %H:%M:%S %Y", t)


def asctime(t=None):
    return strftime("%a %b %d %H:%M:%S %Y", t)
