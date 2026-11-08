# Bridge from Python to the app: every call is a JSON request answered synchronously.
import json
import _lumen

_current_plugin = [None]


def native(op, **kwargs):
    if _current_plugin[0] is not None and "plugin" not in kwargs:
        kwargs["plugin"] = _current_plugin[0]
    raw = _lumen.native_call(op, json.dumps(kwargs))
    if raw is None or raw == "null" or raw == "":
        return None
    result = json.loads(raw)
    if isinstance(result, dict) and "__error__" in result:
        raise RuntimeError(result["__error__"])
    return result


def current_plugin():
    return _current_plugin[0]


def set_current_plugin(plugin_id):
    previous = _current_plugin[0]
    _current_plugin[0] = plugin_id
    return previous


def log(text):
    native("log", text=str(text))
