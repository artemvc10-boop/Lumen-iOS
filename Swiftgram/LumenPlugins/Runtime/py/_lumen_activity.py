# Android Activity / Intent / Uri / ContentResolver, as far as plugins use them on iOS:
# picking a photo or file (startActivityForResult -> the iOS picker -> onActivityResult),
# opening links and sharing files, and reading/writing what was picked.
import os
from _lumen_bridge import native
from _lumen_java import JavaStub

_state = {"dialog_id": 0}


def set_current_dialog(dialog_id):
    _state["dialog_id"] = int(dialog_id or 0)


# MARK: Uri / Intent

class Uri(object):
    def __init__(self, value=""):
        self._value = str(value)

    @staticmethod
    def parse(value):
        return Uri(value)

    @staticmethod
    def fromFile(file):
        path = file.getAbsolutePath() if hasattr(file, "getAbsolutePath") else str(file)
        return Uri("file://" + path)

    def getPath(self):
        if self._value.startswith("file://"):
            return self._value[len("file://"):]
        return self._value

    def getScheme(self):
        return self._value.split(":", 1)[0] if ":" in self._value else ""

    def getLastPathSegment(self):
        return os.path.basename(self.getPath())

    def toString(self):
        return self._value

    def __str__(self):
        return self._value

    def __bool__(self):
        return bool(self._value)


class Intent(object):
    ACTION_GET_CONTENT = "android.intent.action.GET_CONTENT"
    ACTION_OPEN_DOCUMENT = "android.intent.action.OPEN_DOCUMENT"
    ACTION_PICK = "android.intent.action.PICK"
    ACTION_VIEW = "android.intent.action.VIEW"
    ACTION_SEND = "android.intent.action.SEND"
    ACTION_SEND_MULTIPLE = "android.intent.action.SEND_MULTIPLE"
    CATEGORY_OPENABLE = "android.intent.category.OPENABLE"
    EXTRA_STREAM = "android.intent.extra.STREAM"
    EXTRA_TEXT = "android.intent.extra.TEXT"
    EXTRA_ALLOW_MULTIPLE = "android.intent.extra.ALLOW_MULTIPLE"
    FLAG_ACTIVITY_NEW_TASK = 268435456
    FLAG_GRANT_READ_URI_PERMISSION = 1

    def __init__(self, action=None, data=None, *args):
        self._action = action if isinstance(action, str) else None
        self._data = data if isinstance(data, Uri) else None
        self._type = None
        self._extras = {}

    def setAction(self, action):
        self._action = action
        return self

    def getAction(self):
        return self._action

    def setType(self, mime):
        self._type = str(mime)
        return self

    def getType(self):
        return self._type

    def setData(self, data):
        self._data = data
        return self

    def setDataAndType(self, data, mime):
        self._data = data
        self._type = str(mime)
        return self

    def getData(self):
        return self._data

    def putExtra(self, key, value):
        self._extras[key] = value
        return self

    def putParcelableArrayListExtra(self, key, value):
        self._extras[key] = value
        return self

    def getExtras(self):
        return JavaStub("Bundle")

    def addCategory(self, category):
        return self

    def addFlags(self, flags):
        return self

    def setFlags(self, flags):
        return self

    @staticmethod
    def createChooser(intent, title=None):
        return intent


# MARK: Streams over picked files

class _InStream(object):
    def __init__(self, path):
        import _lumen_io
        self._data = _lumen_io.read_bytes(path)
        self._pos = 0

    def read(self, buf=None, *args):
        if buf is None:
            if self._pos >= len(self._data):
                return -1
            value = self._data[self._pos]
            self._pos += 1
            return value
        remaining = len(self._data) - self._pos
        if remaining <= 0:
            return -1
        n = min(len(buf), remaining)
        chunk = self._data[self._pos:self._pos + n]
        try:
            buf[0:n] = chunk
        except Exception:
            for i in range(n):
                buf[i] = chunk[i]
        self._pos += n
        return n

    def readAllBytes(self):
        chunk = self._data[self._pos:]
        self._pos = len(self._data)
        return chunk

    def available(self):
        return len(self._data) - self._pos

    def close(self):
        pass


class ContentResolver(object):
    def getType(self, uri):
        ext = os.path.splitext(uri.getPath() if hasattr(uri, "getPath") else str(uri))[1].lower()
        return {".png": "image/png", ".webp": "image/webp", ".gif": "image/gif", ".jpg": "image/jpeg",
                ".jpeg": "image/jpeg", ".heic": "image/heic", ".mp4": "video/mp4", ".mov": "video/quicktime",
                ".zip": "application/zip"}.get(ext, "application/octet-stream")

    def openInputStream(self, uri):
        return _InStream(uri.getPath() if hasattr(uri, "getPath") else str(uri))

    def openOutputStream(self, uri, *args):
        from java.io import FileOutputStream
        return FileOutputStream(uri.getPath() if hasattr(uri, "getPath") else str(uri))

    def query(self, *args, **kwargs):
        return None


# MARK: Activity / fragment

_results = {"hooks": []}
# Direct one-shot callbacks keyed by request code (lumen.media.pick).
_direct_results = {}


def register_direct_result(request_code, callback):
    _direct_results[int(request_code)] = callback


class Activity(object):
    """The single activity plugins see; truthy so 'if not activity: return' passes."""

    def __bool__(self):
        return True

    def startActivityForResult(self, intent, request_code, *args):
        mime = intent.getType() if hasattr(intent, "getType") else None
        native("pickMedia", requestCode=int(request_code), mime=mime or "*/*")

    def startActivity(self, intent, *args):
        action = intent.getAction() if hasattr(intent, "getAction") else None
        data = intent.getData() if hasattr(intent, "getData") else None
        if action == Intent.ACTION_VIEW and data is not None:
            native("openUrl", url=str(data))
        elif action in (Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE):
            stream = intent._extras.get(Intent.EXTRA_STREAM)
            items = stream if isinstance(stream, list) else ([stream] if stream is not None else [])
            paths = [u.getPath() if hasattr(u, "getPath") else str(u) for u in items]
            text = intent._extras.get(Intent.EXTRA_TEXT)
            native("share", paths=paths, text=None if text is None else str(text))

    def getContentResolver(self):
        return ContentResolver()

    def runOnUiThread(self, runnable):
        import _lumen_host
        _lumen_host.defer_runnable(runnable, 0)

    def getApplicationContext(self):
        return self

    def getPackageName(self):
        return "com.artem.lumen"

    def getString(self, *args):
        return ""

    def getWindow(self):
        return JavaStub("Window")

    def getResources(self):
        return JavaStub("Resources")

    def getSystemService(self, *args):
        return JavaStub("Service")

    def isFinishing(self):
        return False

    def __getattr__(self, key):
        if key.startswith("_"):
            raise AttributeError(key)
        return JavaStub("Activity." + key)


_activity = Activity()


class _FragmentClass(object):
    def getName(self):
        return "org.telegram.ui.ChatActivity" if _state["dialog_id"] else "org.telegram.ui.DialogsActivity"

    def getSimpleName(self):
        return self.getName().split(".")[-1]


class Fragment(object):
    def __bool__(self):
        return True

    def getParentActivity(self):
        return _activity

    def getContext(self):
        return _activity

    def getDialogId(self):
        return _state["dialog_id"]

    def getCurrentAccount(self):
        return 0

    def getClass(self):
        return _FragmentClass()

    def presentFragment(self, *args, **kwargs):
        return False

    def showDialog(self, dialog, *args):
        show = getattr(dialog, "show", None)
        if callable(show):
            show()
        return dialog

    def __getattr__(self, key):
        if key.startswith("_"):
            raise AttributeError(key)
        return JavaStub("Fragment." + key)


_fragment = Fragment()


def current_activity():
    return _activity


def current_fragment():
    return _fragment


# MARK: onActivityResult, via the plugin's hook on LaunchActivity

class _FakeMethod(object):
    def __init__(self, name):
        self._name = name

    def getName(self):
        return self._name

    def setAccessible(self, value):
        pass

    def getParameterTypes(self):
        return []


class _LaunchActivityClass(object):
    """What find_class("org.telegram.ui.LaunchActivity") gives: enough for a plugin to find
    onActivityResult and hook it, which is how pickers report back on Android."""

    def __bool__(self):
        return True

    def getClass(self):
        return self

    def getName(self):
        return "org.telegram.ui.LaunchActivity"

    def getDeclaredMethods(self):
        return [_FakeMethod("onActivityResult")]

    def getMethods(self):
        return self.getDeclaredMethods()

    def getSuperclass(self):
        return None

    def getDeclaredMethod(self, name, *args):
        return _FakeMethod(name)

    def getMethod(self, name, *args):
        return _FakeMethod(name)


def is_activity_result_method(method):
    return isinstance(method, _FakeMethod) and method.getName() == "onActivityResult"


def add_result_hook(plugin_id, hook):
    _results["hooks"].append((plugin_id, hook))


def remove_plugin_hooks(plugin_id):
    _results["hooks"] = [h for h in _results["hooks"] if h[0] != plugin_id]


class _HookParam(object):
    def __init__(self, args):
        self.args = args
        self.thisObject = _activity
        self._result = None

    def getResult(self):
        return self._result

    def setResult(self, value):
        self._result = value


def deliver_result(request_code, path, mime):
    import _lumen_host
    direct = _direct_results.pop(int(request_code), None)
    if direct is not None:
        _lumen_host.safe_call(direct, path, mime)
        return
    if path:
        data = Intent()
        data.setDataAndType(Uri("file://" + str(path)), mime or "*/*")
        result_code = -1  # RESULT_OK
    else:
        data = None
        result_code = 0  # RESULT_CANCELED
    for plugin_id, hook in list(_results["hooks"]):
        param = _HookParam([request_code, result_code, data])
        before = getattr(hook, "before_hooked_method", None)
        after = getattr(hook, "after_hooked_method", None)
        if callable(before):
            _lumen_host.run_as(plugin_id, "onActivityResult", before, param)
        if callable(after):
            _lumen_host.run_as(plugin_id, "onActivityResult", after, param)
