# exteraGram android_utils.
from _lumen_bridge import native, log as _log


def log(*args, **kwargs):
    _log(" ".join(str(a) for a in args))


def run_on_ui_thread(fn, delay=0, *args, **kwargs):
    import _lumen_host
    _lumen_host.defer(fn, delay)


def copy_to_clipboard(text, *args, **kwargs):
    native("clipboard", text=str(text))
    return True


class OnClickListener(object):
    def __init__(self, fn):
        self._fn = fn

    def onClick(self, view=None):
        if self._fn is not None:
            self._fn(view)


class OnLongClickListener(object):
    def __init__(self, fn):
        self._fn = fn

    def onLongClick(self, view=None):
        if self._fn is not None:
            return self._fn(view)
        return False


class R(object):
    """Runnable wrapper used by some plugins: R(lambda: ...)."""

    def __init__(self, fn):
        self._fn = fn

    def run(self):
        if self._fn is not None:
            self._fn()
