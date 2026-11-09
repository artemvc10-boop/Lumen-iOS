# TL objects for plugins, shaped like Android's TLRPC classes.
#
# The app hands requests, responses and updates over as JSON built from the schema (see
# LumenTLJSON.swift): {"_": "messages.sendMessage", "message": "hi", "random_id": {"#l": "..."}}.
# Here they become objects with attribute access (`request.message`, `request.peer.user_id`),
# `true` flags as booleans (`request.silent = True`), Android class names
# (`request.getClass().getSimpleName() == "TL_messages_sendMessage"`) and isinstance checks
# against `TLRPC.TL_messages_sendMessage`.
import base64
import _lumen_tl_flags

_NAMESPACES = set([
    "account", "auth", "bots", "channels", "chatlists", "contacts", "folders", "fragment",
    "help", "langpack", "messages", "payments", "phone", "photos", "premium", "smsjobs",
    "stats", "stickers", "stories", "updates", "upload", "users",
])

_INT32_MIN = -2147483648
_INT32_MAX = 2147483647


def android_name(constructor):
    """`messages.sendMessage` -> `TL_messages_sendMessage`."""
    return "TL_" + constructor.replace(".", "_")


def schema_name(android):
    """`TL_messages_sendMessage` -> `messages.sendMessage`."""
    name = android[3:] if android.startswith("TL_") else android
    head = name.split("_", 1)
    if len(head) == 2 and head[0] in _NAMESPACES:
        return head[0] + "." + head[1]
    return name


class _JavaClass(object):
    def __init__(self, simple):
        self._simple = simple

    def getSimpleName(self):
        return self._simple

    def getName(self):
        return "org.telegram.tgnet.TLRPC$" + self._simple

    def __repr__(self):
        return "class " + self.getName()


class TLObject(object):
    """A TL constructor value. Missing fields read as None, like Android's null/0."""

    _tl_constructor = None

    def __init__(self, *args, **fields):
        constructor = self._tl_constructor
        if args:
            constructor = args[0]
        self.__dict__["_tl_name"] = constructor or ""
        self.__dict__["_tl_fields"] = {}
        for key in fields:
            setattr(self, key, fields[key])

    def __getattr__(self, name):
        if name.startswith("__") or name.startswith("_tl_"):
            raise AttributeError(name)
        fields = self.__dict__["_tl_fields"]
        if name in fields:
            return fields[name]
        flag = _lumen_tl_flags.true_flags(self.__dict__["_tl_name"]).get(name)
        if flag is not None:
            return (int(fields.get(flag[0]) or 0) >> flag[1]) & 1 == 1
        return None

    def __setattr__(self, name, value):
        if name.startswith("_tl_"):
            self.__dict__[name] = value
            return
        fields = self.__dict__["_tl_fields"]
        flag = _lumen_tl_flags.true_flags(self.__dict__["_tl_name"]).get(name)
        if flag is not None:
            current = int(fields.get(flag[0]) or 0)
            if value:
                current = current | (1 << flag[1])
            else:
                current = current & ~(1 << flag[1])
            fields[flag[0]] = current & 0xFFFFFFFF
            return
        fields[name] = value

    def __delattr__(self, name):
        self.__dict__["_tl_fields"].pop(name, None)

    def tl_name(self):
        return self.__dict__["_tl_name"]

    def tl_fields(self):
        return dict(self.__dict__["_tl_fields"])

    def getClass(self):
        return _JavaClass(android_name(self.__dict__["_tl_name"]))

    def getConstructor(self):
        return self.__dict__["_tl_name"]

    def to_dict(self):
        return to_json(self)

    def __eq__(self, other):
        return isinstance(other, TLObject) and to_json(self) == to_json(other)

    def __ne__(self, other):
        return not self.__eq__(other)

    def __hash__(self):
        return id(self)

    def __repr__(self):
        parts = []
        for key in sorted(self.__dict__["_tl_fields"]):
            parts.append("%s=%r" % (key, self.__dict__["_tl_fields"][key]))
        return android_name(self.__dict__["_tl_name"]) + "(" + ", ".join(parts) + ")"


_classes = {}


def class_for(constructor):
    """The Python class for a constructor, created once, so isinstance checks work."""
    cls = _classes.get(constructor)
    if cls is None:
        cls = type(android_name(constructor), (TLObject,), {"_tl_constructor": constructor})
        _classes[constructor] = cls
    return cls


def new(constructor, **fields):
    """lumen-style constructor: new("messageEntityBold", offset=0, length=4)."""
    return class_for(constructor)(**fields)


class _TLRPC(object):
    """`TLRPC.TL_messages_sendMessage` is a class: call it to build one, or isinstance-check."""

    def __getattr__(self, name):
        if name.startswith("__"):
            raise AttributeError(name)
        return class_for(schema_name(name))


TLRPC = _TLRPC()


class TL_error(object):
    def __init__(self, code=0, text=""):
        self.code = int(code or 0)
        self.text = str(text or "")

    def __repr__(self):
        return "TL_error(%d, %s)" % (self.code, self.text)


# MARK: JSON

def from_json(value):
    if isinstance(value, dict):
        if "_" in value:
            obj = class_for(str(value["_"]))()
            fields = obj.__dict__["_tl_fields"]
            for key in value:
                if key != "_":
                    fields[key] = from_json(value[key])
            return obj
        if "#l" in value and len(value) == 1:
            return int(value["#l"])
        if "#b" in value and len(value) == 1:
            return base64.b64decode(value["#b"])
        return dict((k, from_json(v)) for k, v in value.items())
    if isinstance(value, list):
        return [from_json(v) for v in value]
    return value


def to_json(value):
    if isinstance(value, TLObject):
        result = {"_": value.__dict__["_tl_name"]}
        fields = value.__dict__["_tl_fields"]
        for key in fields:
            item = fields[key]
            if item is not None:
                result[key] = to_json(item)
        return result
    if value is True or value is False:
        return value
    if isinstance(value, int):
        if value < _INT32_MIN or value > _INT32_MAX:
            return {"#l": str(value)}
        return value
    if isinstance(value, bytes):
        encoded = base64.b64encode(value)
        if isinstance(encoded, bytes):
            encoded = encoded.decode("ascii")
        return {"#b": encoded}
    if isinstance(value, (list, tuple)):
        return [to_json(v) for v in value]
    if isinstance(value, dict):
        return dict((k, to_json(v)) for k, v in value.items())
    return value
