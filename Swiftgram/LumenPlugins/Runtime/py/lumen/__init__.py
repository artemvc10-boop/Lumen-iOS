# Lumen-only plugin API: things that exist on iOS and have no exteraGram equivalent.
#
#   import lumen
#   if lumen.IS_IOS:
#       lumen.set_app_setting("forceClearGlass", True)
from _lumen_bridge import native

IS_IOS = True

# App settings a plugin may change. Unknown keys are refused.
#   forceClearGlass  clear (transparent) Liquid Glass panels in chats
#   fakeGlass        Telegram's own simplified glass instead of the system one (faster)
APP_SETTINGS = ("forceClearGlass", "fakeGlass")


def get_app_setting(key, default=None):
    value = native("getAppSetting", key=str(key))
    return default if value is None else value


def set_app_setting(key, value):
    return bool(native("setAppSetting", key=str(key), value=value))
