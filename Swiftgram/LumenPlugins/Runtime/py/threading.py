# threading: plugins run on a single serial queue, so a Thread runs its target on that
# queue right after the current call returns. Locks are no-ops.


class Lock(object):
    def acquire(self, blocking=True, timeout=-1):
        return True

    def release(self):
        pass

    def locked(self):
        return False

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


RLock = Lock


class Event(object):
    def __init__(self):
        self._flag = False

    def set(self):
        self._flag = True

    def clear(self):
        self._flag = False

    def is_set(self):
        return self._flag

    isSet = is_set

    def wait(self, timeout=None):
        return self._flag


class Condition(Lock):
    def wait(self, timeout=None):
        return True

    def notify(self, n=1):
        pass

    def notify_all(self):
        pass


class Semaphore(Lock):
    def __init__(self, value=1):
        pass


BoundedSemaphore = Semaphore


class Thread(object):
    def __init__(self, group=None, target=None, name=None, args=(), kwargs=None, daemon=None):
        self._target = target
        self._args = args
        self._kwargs = kwargs or {}
        self.name = name or "Thread"
        self.daemon = daemon
        self._started = False

    def run(self):
        if self._target is not None:
            self._target(*self._args, **self._kwargs)

    def start(self):
        import _lumen_host
        self._started = True
        _lumen_host.defer(self.run, 0)

    def join(self, timeout=None):
        pass

    def is_alive(self):
        return False

    def setDaemon(self, value):
        self.daemon = value


class Timer(Thread):
    def __init__(self, interval, function, args=None, kwargs=None):
        Thread.__init__(self, target=function, args=args or (), kwargs=kwargs)
        self._interval = interval
        self._cancelled = False

    def start(self):
        import _lumen_host
        _lumen_host.defer(self._fire, self._interval)

    def _fire(self):
        if not self._cancelled:
            self.run()

    def cancel(self):
        self._cancelled = True


class local(object):
    pass


def current_thread():
    return Thread(name="MainThread")


def main_thread():
    return current_thread()


def get_ident():
    return 1


def active_count():
    return 1
