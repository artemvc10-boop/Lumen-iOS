# contextlib for Skulpt.


class _GeneratorContextManager(object):
    def __init__(self, func, args, kwargs):
        self._gen = func(*args, **kwargs)

    def __enter__(self):
        try:
            return next(self._gen)
        except StopIteration:
            raise RuntimeError("generator didn't yield")

    def __exit__(self, exc_type, exc_value, tb):
        if exc_type is None:
            try:
                next(self._gen)
            except StopIteration:
                return False
            raise RuntimeError("generator didn't stop")
        if exc_value is None:
            exc_value = exc_type()
        try:
            self._gen.throw(exc_value)
        except StopIteration:
            return True
        except BaseException as error:
            if error is exc_value:
                return False
            raise
        raise RuntimeError("generator didn't stop after throw()")


def contextmanager(func):
    def helper(*args, **kwargs):
        return _GeneratorContextManager(func, args, kwargs)
    helper.__name__ = getattr(func, "__name__", "helper")
    return helper


class suppress(object):
    def __init__(self, *exceptions):
        self._exceptions = exceptions

    def __enter__(self):
        return None

    def __exit__(self, exc_type, exc_value, tb):
        return exc_type is not None and issubclass(exc_type, self._exceptions)


class closing(object):
    def __init__(self, thing):
        self.thing = thing

    def __enter__(self):
        return self.thing

    def __exit__(self, *args):
        self.thing.close()
        return False


class nullcontext(object):
    def __init__(self, enter_result=None):
        self.enter_result = enter_result

    def __enter__(self):
        return self.enter_result

    def __exit__(self, *args):
        return False


class ExitStack(object):
    def __init__(self):
        self._callbacks = []

    def enter_context(self, cm):
        result = cm.__enter__()
        self._callbacks.append(lambda: cm.__exit__(None, None, None))
        return result

    def callback(self, fn, *args, **kwargs):
        self._callbacks.append(lambda: fn(*args, **kwargs))
        return fn

    def close(self):
        while self._callbacks:
            self._callbacks.pop()()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
        return False
