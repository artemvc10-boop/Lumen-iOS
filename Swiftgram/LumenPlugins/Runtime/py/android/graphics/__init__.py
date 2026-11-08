# android.graphics
from _lumen_java import JavaStub


class Bitmap(object):
    class Config(object):
        ARGB_8888 = "ARGB_8888"

    def __init__(self, path=None, width=0, height=0):
        self._lumen_path = path
        self._w = width
        self._h = height

    def getWidth(self):
        return self._w or 1

    def getHeight(self):
        return self._h or 1

    def recycle(self):
        pass

    @staticmethod
    def createScaledBitmap(src, width, height, filter=True):
        return Bitmap(getattr(src, "_lumen_path", None), width, height)

    @staticmethod
    def createBitmap(*args, **kwargs):
        return Bitmap(None, 1, 1)


class BitmapFactory(object):
    class Options(object):
        def __init__(self):
            self.inJustDecodeBounds = False
            self.inSampleSize = 1
            self.outWidth = 0
            self.outHeight = 0

    @staticmethod
    def decodeFile(path, opts=None):
        # Bounds-only pass: the app fills real dimensions so inSampleSize math works.
        if opts is not None and getattr(opts, "inJustDecodeBounds", False):
            from _lumen_bridge import native
            info = native("imageSize", path=str(path)) or {}
            opts.outWidth = int(info.get("width", 0))
            opts.outHeight = int(info.get("height", 0))
            return None
        return Bitmap(str(path))

    @staticmethod
    def decodeResource(*args, **kwargs):
        return None


class _TypefaceMeta(type):
    # Typeface.DEFAULT, DEFAULT_BOLD, MONOSPACE, SANS_SERIF ... — any constant is inert.
    def __getattr__(cls, key):
        if key.startswith("__") and key.endswith("__"):
            raise AttributeError(key)
        if key in ("NORMAL", "BOLD", "ITALIC", "BOLD_ITALIC"):
            return 0
        return None


class Typeface(metaclass=_TypefaceMeta):
    @staticmethod
    def create(*args, **kwargs):
        return None

    @staticmethod
    def createFromAsset(*args, **kwargs):
        return None

    @staticmethod
    def defaultFromStyle(style=0):
        return None


class Color(object):
    WHITE = -1
    BLACK = -16777216
    TRANSPARENT = 0

    @staticmethod
    def parseColor(value):
        text = str(value).lstrip("#")
        try:
            n = int(text, 16)
            if len(text) <= 6:
                n |= 0xFF000000
            return n - (1 << 32) if n >= (1 << 31) else n
        except Exception:
            return 0

    @staticmethod
    def argb(a, r, g, b):
        return (int(a) << 24) | (int(r) << 16) | (int(g) << 8) | int(b)

    @staticmethod
    def rgb(r, g, b):
        return Color.argb(255, r, g, b)


class PorterDuff(object):
    class Mode(object):
        SRC_IN = "SRC_IN"
        MULTIPLY = "MULTIPLY"


class PorterDuffColorFilter(object):
    def __init__(self, *args, **kwargs):
        pass


class Canvas(JavaStub):
    pass
