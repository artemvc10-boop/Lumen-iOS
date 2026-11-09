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

import _lumen_bytearray
_lumen.install_builtin("bytearray", _lumen_bytearray.bytearray)


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
    text = type(error).__name__ + ": " + str(error)
    try:
        where = _lumen.traceback_of(error)
        if where:
            text += " (" + where + ")"
    except Exception:
        pass
    return text


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


# View callbacks fire many times (taps on a live sheet), so they are not one-shot.
_persistent = set()


def register_view_callback(fn):
    callback_id = register_callback(fn)
    _persistent.add(callback_id)
    return callback_id


def safe_call(fn, *args):
    plugin_id = bridge.current_plugin()
    _run(plugin_id, "callback", fn, *args)


def run_as(plugin_id, what, fn, *args):
    return _run(plugin_id, what, fn, *args)


def defer_runnable(runnable, delay=0):
    run = getattr(runnable, "run", None)
    if callable(run):
        defer(run, delay)
    elif callable(runnable):
        defer(runnable, delay)


def _refresh_views():
    import _lumen_views
    _lumen_views.refresh_open_dialogs()


def set_view_text(payload):
    import _lumen_views as vt
    request = json.loads(payload)
    vt.set_view_text(request["vid"], request.get("value"))
    _refresh_views()
    return json.dumps({"ok": True})


def screen_event(payload):
    """A native plugin screen reported a tap/edit/search/select."""
    import lumen.ui
    request = json.loads(payload)
    plugin_id = request.get("plugin")
    _run(plugin_id, "screen event", lumen.ui.deliver_event, request)
    _refresh_views()
    return json.dumps({"ok": True})


def activity_result(payload):
    """A picker the plugin opened with startActivityForResult returned."""
    import _lumen_activity
    request = json.loads(payload)
    _lumen_activity.deliver_result(int(request.get("requestCode", 0)), request.get("path"), request.get("mime"))
    _refresh_views()
    return json.dumps({"ok": True})


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
    import _lumen_preprocess
    source = _lumen_preprocess.prepare(source)
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
    push_tl_interest()
    import _lumen_activity
    _lumen_activity.remove_plugin_hooks(plugin_id)
    for callback_id in [k for k, v in _callbacks.items() if v[0] == plugin_id]:
        del _callbacks[callback_id]
        _persistent.discard(callback_id)
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
    import _lumen_activity
    message = request.get("message")
    dialog_id = int(request.get("dialogId", 0))
    _lumen_activity.set_current_dialog(dialog_id)
    context = {"account": 0, "context": _lumen_activity.current_activity(), "fragment": _lumen_activity.current_fragment(),
               "dialog_id": dialog_id, "groupedMessages": [], "user_id": dialog_id if dialog_id > 0 else 0,
               "chat_id": -dialog_id if dialog_id < 0 else 0}
    if message is not None:
        message["dialogId"] = dialog_id
        context["message"] = MessageObject(message)
    media_path = request.get("mediaPath")
    if media_path:
        # The message's media, already copied somewhere the plugin may read it.
        context["filepath"] = str(media_path)
        if message is not None:
            context["message"]._lumen_media_path = str(media_path)
            context["message"].messageOwner._lumen_media_path = str(media_path)
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
    _refresh_views()
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
    callback_id = request["id"]
    entry = _callbacks.get(callback_id)
    if entry is None:
        return json.dumps({"ok": False})
    if callback_id not in _persistent and not request.get("keep", False):
        del _callbacks[callback_id]
    plugin_id, fn = entry
    args = request.get("args") or []
    _run(plugin_id, "callback", fn, *args)
    _refresh_views()
    return json.dumps({"ok": True})


def drop_callback(payload):
    _callbacks.pop(json.loads(payload)["id"], None)
    return json.dumps({"ok": True})


# MARK: Raw TL hooks (pre_request_hook / post_request_hook / on_update_hook)

_last_interest = [None]


def push_tl_interest():
    """Tells the app which request/update names any plugin hooks, so it only converts those."""
    exact = set()
    substrings = set()
    for record in list(_plugins.values()):
        for hook in getattr(record["instance"], "_lumen_hooks", None) or []:
            if hook[1]:
                substrings.add(hook[0])
            else:
                exact.add(hook[0])
    key = (tuple(sorted(exact)), tuple(sorted(substrings)))
    if key == _last_interest[0]:
        return
    _last_interest[0] = key
    bridge.native("setTLHooks", exact=list(key[0]), substrings=list(key[1]))


_TL_METHODS = {"pre": "pre_request_hook", "post": "post_request_hook", "update": "on_update_hook"}


def _tl_chain(name, method):
    records = []
    for record in list(_plugins.values()):
        instance = record["instance"]
        priority = instance.hook_priority(name) if hasattr(instance, "hook_priority") else None
        if priority is None or not callable(getattr(instance, method, None)):
            continue
        records.append((priority, record))
    records.sort(key=lambda pair: -pair[0])
    return [pair[1] for pair in records]


def tl_hook(payload):
    import _lumen_tl
    request = json.loads(payload)
    kind = request.get("kind")
    name = request.get("name", "")
    method = _TL_METHODS.get(kind)
    if method is None:
        return json.dumps({"decision": "keep"})
    chain = _tl_chain(name, method)
    if not chain:
        return json.dumps({"decision": "keep"})
    raw = request.get("data")
    data = json.loads(raw) if raw else None
    if kind == "post":
        value = _lumen_tl.from_json(data.get("result")) if isinstance(data, dict) else None
    else:
        value = _lumen_tl.from_json(data)
    error = None
    if request.get("errorText") is not None:
        error = _lumen_tl.TL_error(request.get("errorCode", 0), request.get("errorText"))
    original_error = error
    changed = False
    for record in chain:
        fn = getattr(record["instance"], method)
        if kind == "post":
            result = _run(record["id"], method, fn, name, 0, value, error)
        else:
            result = _run(record["id"], method, fn, name, 0, value)
        if not isinstance(result, HookResult):
            continue
        if result.strategy == HookStrategy.CANCEL:
            return json.dumps({"decision": "cancel", "plugin": record["id"]})
        if result.strategy in (HookStrategy.MODIFY, HookStrategy.MODIFY_FINAL):
            if kind == "pre" and result.request is not None:
                value = result.request
                changed = True
            elif kind == "update" and result.update is not None:
                value = result.update
                changed = True
            elif kind == "post":
                if result.response is not None:
                    value = result.response
                    error = None
                    changed = True
                elif result.error is not None:
                    error = result.error
                    changed = True
            if result.strategy == HookStrategy.MODIFY_FINAL:
                break
    _refresh_views()
    if not changed:
        return json.dumps({"decision": "keep"})
    if kind == "post" and error is not None:
        if error is original_error:
            return json.dumps({"decision": "keep"})
        return json.dumps({"decision": "error", "code": int(getattr(error, "code", 400) or 400),
                           "text": str(getattr(error, "text", "PLUGIN_ERROR"))})
    return json.dumps({"decision": "replace", "data": _lumen_tl.to_json(value)})
