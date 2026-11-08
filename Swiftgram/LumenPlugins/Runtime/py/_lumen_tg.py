# org.telegram.messenger
from _lumen_java import JavaStub
from _lumen_bridge import native


class AndroidUtilities(object):
    # dp maps to iOS points one to one (both are density-independent).
    @staticmethod
    def dp(value):
        try:
            return int(round(float(value)))
        except Exception:
            return 0

    @staticmethod
    def dpf2(value):
        try:
            return float(value)
        except Exception:
            return 0.0

    density = 1.0

    @staticmethod
    def runOnUIThread(runnable, delay=0):
        import _lumen_host
        _lumen_host.defer_runnable(runnable, delay)

    @staticmethod
    def formatFileSize(size):
        try:
            size = float(size)
        except Exception:
            return "0 B"
        for unit in ["B", "KB", "MB", "GB"]:
            if size < 1024.0:
                return ("%.1f %s" % (size, unit)).replace(".0", "")
            size /= 1024.0
        return "%.1f TB" % size

    def __getattr__(self, key):
        return JavaStub("AndroidUtilities." + key)


class _ThemeMeta(type):
    def __getattr__(cls, key):
        # Theme.key_dialogTextBlack and friends are their own names; getColor maps them.
        if key.startswith("key_"):
            return key
        raise AttributeError(key)


class Theme(metaclass=_ThemeMeta):
    @staticmethod
    def getColor(key, *args, **kwargs):
        return int(native("themeColor", key=str(key)) or 0)

    @staticmethod
    def getColorOrNull(key, *args, **kwargs):
        return Theme.getColor(key)


class _R(object):
    class drawable(object):
        def __getattr__(self, key):
            return 0

    class color(object):
        def __getattr__(self, key):
            return 0

    class string(object):
        def __getattr__(self, key):
            return 0

    class id(object):
        def __getattr__(self, key):
            return 0

    def __getattr__(self, key):
        return _R()


R = _R()
R.drawable = _R.drawable()
R.color = _R.color()
R.string = _R.string()
R.id = _R.id()


class FileLoader(object):
    @staticmethod
    def getInstance(account=0):
        return JavaStub("FileLoader")

    @staticmethod
    def getClosestPhotoSizeWithSize(*args, **kwargs):
        return None


class LocaleController(object):
    @staticmethod
    def getInstance():
        return JavaStub("LocaleController")

    @staticmethod
    def getString(key, resId=0, *args):
        return str(key)


class UserConfig(object):
    @staticmethod
    def getInstance(account=0):
        return JavaStub("UserConfig")

    @staticmethod
    def selectedAccount():
        return 0


class ApplicationLoader(object):
    applicationContext = JavaStub("Context")


class MediaController(JavaStub):
    pass


class MessagesController(JavaStub):
    pass


class Utilities(JavaStub):
    pass


def __getattr__(name):
    # Anything else from this module (classes we do not model) is an inert stub.
    return JavaStub("messenger." + name)
