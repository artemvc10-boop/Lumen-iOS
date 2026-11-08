# org.telegram.messenger
from _lumen_java import JavaStub
from _lumen_bridge import native


class _Point(object):
    def __init__(self, x=0, y=0):
        self.x = x
        self.y = y


_screen = {}


def _screen_info():
    if not _screen:
        info = native("screen") or {}
        _screen["size"] = _Point(int(info.get("width", 390)), int(info.get("height", 844)))
        _screen["statusBar"] = int(info.get("statusBar", 47))
        _screen["bottomInset"] = int(info.get("bottomInset", 34))
    return _screen


class _AndroidUtilitiesMeta(type):
    def __getattr__(cls, key):
        if key.startswith("__") and key.endswith("__"):
            raise AttributeError(key)
        if key == "displaySize":
            return _screen_info()["size"]
        if key == "statusBarHeight":
            return _screen_info()["statusBar"]
        if key == "navigationBarHeight":
            return _screen_info()["bottomInset"]
        if key in ("usingHardwareInput", "isInMultiwindow", "firstConfigurationWas"):
            return False
        return JavaStub("AndroidUtilities." + key)


class AndroidUtilities(metaclass=_AndroidUtilitiesMeta):
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

    @staticmethod
    def isTablet():
        return False

    @staticmethod
    def addToClipboard(text):
        native("clipboard", text=str(text))
        return True

    @staticmethod
    def hideKeyboard(*args):
        pass

    @staticmethod
    def showKeyboard(*args):
        return True

    @staticmethod
    def cancelRunOnUIThread(*args):
        pass

    @staticmethod
    def lerp(a, b, t):
        return a + (b - a) * t

    @staticmethod
    def getPath(uri, *args):
        return uri.getPath() if hasattr(uri, "getPath") else str(uri)


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


class _FileLoaderInstance(object):
    def getPathToMessage(self, owner, *args):
        path = getattr(owner, "_lumen_media_path", None)
        if path:
            from java.io import File
            return File(path)
        return None

    def getPathToAttach(self, attach, *args):
        return self.getPathToMessage(attach)

    def __getattr__(self, key):
        if key.startswith("_"):
            raise AttributeError(key)
        return JavaStub("FileLoader." + key)


class FileLoader(object):
    MEDIA_DIR_IMAGE = 0
    MEDIA_DIR_AUDIO = 1
    MEDIA_DIR_VIDEO = 2
    MEDIA_DIR_DOCUMENT = 3
    MEDIA_DIR_CACHE = 4

    @staticmethod
    def getInstance(account=0):
        return _FileLoaderInstance()

    @staticmethod
    def getClosestPhotoSizeWithSize(*args, **kwargs):
        return None

    @staticmethod
    def getDirectory(kind=0):
        from java.io import File
        return File("/storage/emulated/0/Telegram")


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


