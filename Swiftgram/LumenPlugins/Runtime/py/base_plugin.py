# exteraGram plugin SDK: base_plugin, as far as it can exist on iOS.
from _lumen_bridge import native, log as _log
from _lumen_java import JavaStub


class AppEvent:
    START = "START"
    STOP = "STOP"
    PAUSE = "PAUSE"
    RESUME = "RESUME"


class HookStrategy:
    DEFAULT = "DEFAULT"
    CANCEL = "CANCEL"
    MODIFY = "MODIFY"
    MODIFY_FINAL = "MODIFY_FINAL"


class HookResult(object):
    def __init__(self, strategy=HookStrategy.DEFAULT, request=None, response=None, update=None, updates=None, params=None, error=None):
        self.strategy = strategy
        self.request = request
        self.response = response
        self.update = update
        self.updates = updates
        self.params = params
        self.error = error


class MenuItemType:
    MESSAGE_CONTEXT_MENU = "MESSAGE_CONTEXT_MENU"
    DRAWER_MENU = "DRAWER_MENU"
    CHAT_ACTION_MENU = "CHAT_ACTION_MENU"
    PROFILE_ACTION_MENU = "PROFILE_ACTION_MENU"
    MAIN_MENU = "MAIN_MENU"


class MenuItemData(object):
    def __init__(self, menu_type=MenuItemType.MESSAGE_CONTEXT_MENU, text="", on_click=None, item_id=None, icon=None, subtext=None, condition=None, priority=0, **kwargs):
        self.menu_type = menu_type
        self.text = text
        self.on_click = on_click
        self.item_id = item_id
        self.icon = icon
        self.subtext = subtext
        self.condition = condition
        self.priority = priority


class MethodHook(object):
    def before_hooked_method(self, param):
        pass

    def after_hooked_method(self, param):
        pass


class MethodReplacement(MethodHook):
    def replace_hooked_method(self, param):
        return None


XposedHook = MethodHook


class HookFilter:
    """Hook filters narrow Java method hooks, which cannot exist on iOS."""

    @staticmethod
    def RESULT_IS_NULL(*args, **kwargs):
        return None

    RESULT_IS_TRUE = RESULT_IS_NULL
    RESULT_IS_FALSE = RESULT_IS_NULL
    RESULT_NOT_NULL = RESULT_IS_NULL
    RESULT_EQUAL = RESULT_IS_NULL
    RESULT_NOT_EQUAL = RESULT_IS_NULL
    RESULT_IS_INSTANCE_OF = RESULT_IS_NULL
    ARGUMENT_IS_NULL = RESULT_IS_NULL
    ARGUMENT_IS_TRUE = RESULT_IS_NULL
    ARGUMENT_IS_FALSE = RESULT_IS_NULL
    ARGUMENT_NOT_NULL = RESULT_IS_NULL
    ARGUMENT_EQUAL = RESULT_IS_NULL
    ARGUMENT_NOT_EQUAL = RESULT_IS_NULL
    ARGUMENT_IS_INSTANCE_OF = RESULT_IS_NULL
    CONDITION = RESULT_IS_NULL
    OR = RESULT_IS_NULL


def hook_filters(*args, **kwargs):
    def wrap(fn):
        return fn
    return wrap


class _Unhook(object):
    def unhook(self):
        pass


class PluginError(Exception):
    pass


_missing = object()


class _Logger(object):
    """The plugin logger (BasePlugin.logger) from the SDK."""

    def _write(self, level, message, *args):
        text = str(message)
        if args:
            try:
                text = text % args
            except Exception:
                text = text + " " + " ".join(str(a) for a in args)
        _log(level + text)

    def debug(self, message, *args, **kwargs):
        self._write("", message, *args)

    def info(self, message, *args, **kwargs):
        self._write("", message, *args)

    def warning(self, message, *args, **kwargs):
        self._write("⚠️ ", message, *args)

    warn = warning

    def error(self, message, *args, **kwargs):
        self._write("❌ ", message, *args)

    def exception(self, message, *args, **kwargs):
        self._write("❌ ", message, *args)


class BasePlugin(object):
    logger = _Logger()

    def __init__(self, *args, **kwargs):
        pass

    # Lifecycle, overridden by plugins.
    def on_plugin_load(self):
        pass

    def on_plugin_unload(self):
        pass

    def on_app_event(self, event_type):
        pass

    def create_settings(self):
        return []

    # Logging and settings.
    def log(self, message, *args, **kwargs):
        _log(message)

    def get_setting(self, key, default=None):
        value = native("getSetting", key=str(key))
        if value is None:
            return default
        return value

    def set_setting(self, key, value, reload_settings=False):
        native("setSetting", key=str(key), value=value, reload=bool(reload_settings))

    def get_all_settings(self):
        return native("getAllSettings") or {}

    def export_settings(self):
        return self.get_all_settings()

    def import_settings(self, settings, reload_settings=True):
        for key in settings:
            self.set_setting(key, settings[key])

    # Menu items.
    def add_menu_item(self, menu_item_data):
        import _lumen_host
        return _lumen_host.add_menu_item(self, menu_item_data)

    def remove_menu_item(self, item_id):
        import _lumen_host
        return _lumen_host.remove_menu_item(self, item_id)

    # Hooks.
    def add_on_send_message_hook(self, priority=0):
        self._lumen_send_hook = True
        self._lumen_send_priority = priority

    def remove_on_send_message_hook(self):
        self._lumen_send_hook = False

    def add_hook(self, name, match_substring=False, priority=0):
        hooks = getattr(self, "_lumen_hooks", None)
        if hooks is None:
            hooks = []
            self._lumen_hooks = hooks
        hooks.append((str(name), bool(match_substring)))

    def remove_hook(self, name):
        hooks = getattr(self, "_lumen_hooks", None) or []
        self._lumen_hooks = [h for h in hooks if h[0] != name]

    def wants_hook(self, name):
        for hook_name, substring in getattr(self, "_lumen_hooks", None) or []:
            if hook_name == name or (substring and hook_name in name):
                return True
        return False

    # Java method hooking has no iOS equivalent; these succeed and do nothing.
    def hook_method(self, method, hook, priority=0, *args, **kwargs):
        import _lumen_activity
        # onActivityResult is how pickers report back; Lumen delivers those itself.
        if _lumen_activity.is_activity_result_method(method):
            _lumen_activity.add_result_hook(getattr(self, "id", None), hook)
            return _Unhook()
        self._lumen_note_java_hook()
        return None

    def hook_all_methods(self, cls, name, hook, *args, **kwargs):
        if name == "onActivityResult" and getattr(cls, "getName", None) is not None:
            import _lumen_activity
            _lumen_activity.add_result_hook(getattr(self, "id", None), hook)
            return [_Unhook()]
        self._lumen_note_java_hook()
        return []

    def hook_all_constructors(self, cls, hook, *args, **kwargs):
        self._lumen_note_java_hook()
        return []

    def unhook_method(self, unhook):
        pass

    def add_intent_hook(self, *args, **kwargs):
        return None

    def remove_intent_hook(self, *args, **kwargs):
        pass

    def add_file_hook(self, *args, **kwargs):
        return None

    def remove_file_hook(self, *args, **kwargs):
        pass

    def _lumen_note_java_hook(self):
        if not getattr(self, "_lumen_java_hook_noted", False):
            self._lumen_java_hook_noted = True
            _log("перехват Java-методов на iOS недоступен, эта часть плагина не работает")
