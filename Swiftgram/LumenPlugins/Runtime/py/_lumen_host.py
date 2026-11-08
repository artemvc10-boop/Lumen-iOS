# The side of the plugin runtime the app talks to. Every function takes and returns a JSON
# string; see host.js and LumenPluginManager.swift.
import json
import _lumen
import _lumen_bridge as bridge
import _lumen_java
import _lumen_io
from base_plugin import BasePlugin, HookStrategy, HookResult
from _lumen_java import JavaStub
from _lumen_messages import MessageObject, TLMessage, SendMessageParams, Update

_lumen.install_open(_lumen_io.lumen_open)


# Skulpt's json has dumps/loads only.
def _json_dump(obj, fp, *args, **kwargs):
    fp.write(json.dumps(obj, *args, **kwargs))


def _json_load(fp, *args, **kwargs):
    return json.loads(fp.read(), *args, **kwargs)


json.dump = _json_dump
json.load = _json_load

_plugins = {}
_callbacks = {}
_counter = [0]


def _next_id():
    _counter[0] += 1
    return _counter[0]


def _error_text(error):
    return type(error).__name__ + ": " + str(error)


def _run(plugin_id, what, fn, *args):
    """Runs plugin code with its id set for the bridge; logs and swallows its errors."""
    previous = bridge.set_current_plugin(plugin_id)
    try:
        return fn(*args)
    except Exception as error:
        bridge.native("pluginError", plugin=plugin_id, text=what + ": " + _error_text(error))
        return None
    finally:
        bridge.set_current_plugin(previous)


def register_callback(fn):
    callback_id = _next_id()
    _callbacks[callback_id] = (bridge.current_plugin(), fn)
    return callback_id


def defer(fn, delay=0):
    callback_id = register_callback(fn)
    try:
        delay = float(delay or 0)
    except Exception:
        delay = 0.0
    bridge.native("defer", id=callback_id, delay=delay / 1000.0 if delay > 50 else delay)


def _record_of(plugin):
    return _plugins.get(getattr(plugin, "id", None))


# MARK: Menu items

def _menu_json(record):
    items = []
    for item_id, data in record["menu"].items():
        items.append({"itemId": item_id, "type": str(data.menu_type), "text": str(data.text),
                      "subtext": None if data.subtext is None else str(data.subtext),
                      "icon": None if data.icon is None else str(data.icon), "priority": int(data.priority or 0)})
    return items


def _push_menu(record):
    bridge.native("menuChanged", plugin=record["id"], items=_menu_json(record))


def menu_items(payload):
    """Returns the current menu items of one plugin (the app reads this when it needs them)."""
    record = _plugins.get(json.loads(payload)["plugin"])
    if record is None:
        return json.dumps({"items": []})
    return json.dumps({"items": _menu_json(record)})


def add_menu_item(plugin, data):
    record = _record_of(plugin)
    if record is None:
        return None
    item_id = data.item_id or (record["id"] + ":" + str(_next_id()))
    data.item_id = item_id
    record["menu"][item_id] = data
    _push_menu(record)
    return item_id


def remove_menu_item(plugin, item_id):
    record = _record_of(plugin)
    if record is None or item_id not in record["menu"]:
        return False
    del record["menu"][item_id]
    _push_menu(record)
    return True


# MARK: Loading

def _find_plugin_class(module):
    candidates = []
    for name in dir(module):
        value = getattr(module, name, None)
        try:
            if isinstance(value, type) and issubclass(value, BasePlugin) and value is not BasePlugin:
                candidates.append(value)
        except Exception:
            pass
    # Prefer the most derived class: a module may import helper base classes.
    for cls in candidates:
        if not any(other is not cls and issubclass(other, cls) for other in candidates):
            return cls
    return None


def load_plugin(payload):
    request = json.loads(payload)
    plugin_id = request["id"]
    if plugin_id in _plugins:
        return json.dumps({"ok": True})
    source = request["source"]
    module_name = "lumen_plugin_" + "".join(c if c.isalnum() else "_" for c in plugin_id)
    _lumen_java.scan_imports(source)
    _lumen.set_file(request.get("path", ""))
    previous = bridge.set_current_plugin(plugin_id)
    try:
        module = _lumen.load_module(module_name, source)
        cls = _find_plugin_class(module)
        if cls is None:
            _lumen.forget_module(module_name)
            return json.dumps({"error": "в файле нет класса, унаследованного от BasePlugin"})
        instance = cls()
        instance.id = plugin_id
        instance.name = request.get("name", plugin_id)
        record = {"id": plugin_id, "module": module_name, "instance": instance, "menu": {}, "handles": {}}
        _plugins[plugin_id] = record
        try:
            instance.on_plugin_load()
        except Exception as error:
            bridge.native("pluginError", plugin=plugin_id, text="on_plugin_load: " + _error_text(error))
        return json.dumps({"ok": True, "menu": _menu_json(record)})
    except Exception as error:
        _plugins.pop(plugin_id, None)
        _lumen.forget_module(module_name)
        return json.dumps({"error": _error_text(error)})
    finally:
        bridge.set_current_plugin(previous)


def unload_plugin(payload):
    plugin_id = json.loads(payload)["id"]
    record = _plugins.pop(plugin_id, None)
    if record is None:
        return json.dumps({"ok": True})
    _run(plugin_id, "on_plugin_unload", record["instance"].on_plugin_unload)
    _lumen.forget_module(record["module"])
    for callback_id in [k for k, v in _callbacks.items() if v[0] == plugin_id]:
        del _callbacks[callback_id]
    return json.dumps({"ok": True})


# MARK: Hooks

def _ordered(attribute):
    records = [r for r in _plugins.values() if getattr(r["instance"], attribute, False)]
    records.sort(key=lambda r: -int(getattr(r["instance"], "_lumen_send_priority", 0) or 0))
    return records


def send_hook(payload):
    request = json.loads(payload)
    params = SendMessageParams(request)
    original = params.message
    for record in _ordered("_lumen_send_hook"):
        result = _run(record["id"], "on_send_message_hook", record["instance"].on_send_message_hook, 0, params)
        if not isinstance(result, HookResult):
            continue
        if result.strategy == HookStrategy.CANCEL:
            return json.dumps({"cancel": True, "plugin": record["id"]})
        if result.strategy in (HookStrategy.MODIFY, HookStrategy.MODIFY_FINAL):
            if result.params is not None:
                params = result.params
            if result.strategy == HookStrategy.MODIFY_FINAL:
                break
    text = params.message if params.message is not None else ""
    return json.dumps({"cancel": False, "text": str(text), "changed": str(text) != original})


def update_hook(payload):
    request = json.loads(payload)
    name = "TL_updateNewChannelMessage" if request.get("isChannel") else "TL_updateNewMessage"
    for record in list(_plugins.values()):
        instance = record["instance"]
        if not instance.wants_hook(name):
            continue
        update = Update(TLMessage(request))
        _run(record["id"], "on_update_hook", instance.on_update_hook, name, 0, update)
    return json.dumps({"ok": True})


def _message_context(request):
    message = request.get("message")
    dialog_id = int(request.get("dialogId", 0))
    context = {"account": 0, "context": JavaStub("Context"), "fragment": JavaStub("ChatActivity"),
               "dialog_id": dialog_id, "groupedMessages": [], "user_id": dialog_id if dialog_id > 0 else 0,
               "chat_id": -dialog_id if dialog_id < 0 else 0}
    if message is not None:
        message["dialogId"] = dialog_id
        context["message"] = MessageObject(message)
    return context


def menu_click(payload):
    request = json.loads(payload)
    record = _plugins.get(request["plugin"])
    if record is None:
        return json.dumps({"error": "плагин не загружен"})
    data = record["menu"].get(request["itemId"])
    if data is None or data.on_click is None:
        return json.dumps({"error": "пункт меню не найден"})
    _run(record["id"], "меню «" + str(data.text) + "»", data.on_click, _message_context(request))
    return json.dumps({"ok": True})


def app_event(payload):
    event = json.loads(payload)["event"]
    for record in list(_plugins.values()):
        _run(record["id"], "on_app_event", record["instance"].on_app_event, event)
    return json.dumps({"ok": True})


# MARK: Settings

def _settings_json(record, items):
    result = []
    for item in items or []:
        try:
            data = item.to_json()
        except Exception:
            continue
        handle = _next_id()
        record["handles"][handle] = item
        data["handle"] = handle
        result.append(data)
    return result


def create_settings(payload):
    plugin_id = json.loads(payload)["plugin"]
    record = _plugins.get(plugin_id)
    if record is None:
        return json.dumps({"error": "плагин не загружен"})
    record["handles"] = {}
    items = _run(plugin_id, "create_settings", record["instance"].create_settings)
    return json.dumps({"items": _settings_json(record, items)})


def settings_sub(payload):
    request = json.loads(payload)
    record = _plugins.get(request["plugin"])
    item = record["handles"].get(request["handle"]) if record else None
    if item is None or getattr(item, "create_sub_fragment", None) is None:
        return json.dumps({"items": []})
    items = _run(record["id"], "create_sub_fragment", item.create_sub_fragment)
    return json.dumps({"items": _settings_json(record, items)})


def settings_event(payload):
    request = json.loads(payload)
    record = _plugins.get(request["plugin"])
    item = record["handles"].get(request["handle"]) if record else None
    if item is None:
        return json.dumps({"ok": False})
    if getattr(item, "kind", "") == "text":
        if item.on_click is not None:
            _run(record["id"], "on_click", item.on_click, JavaStub("View"))
    else:
        handler = getattr(item, "on_change", None)
        if handler is not None:
            _run(record["id"], "on_change", handler, request.get("value"))
    return json.dumps({"ok": True})


# MARK: Callbacks

def run_callback(payload):
    request = json.loads(payload)
    entry = _callbacks.get(request["id"])
    if entry is None:
        return json.dumps({"ok": False})
    if not request.get("keep", False):
        del _callbacks[request["id"]]
    plugin_id, fn = entry
    args = request.get("args") or []
    _run(plugin_id, "callback", fn, *args)
    return json.dumps({"ok": True})


def drop_callback(payload):
    _callbacks.pop(json.loads(payload)["id"], None)
    return json.dumps({"ok": True})
