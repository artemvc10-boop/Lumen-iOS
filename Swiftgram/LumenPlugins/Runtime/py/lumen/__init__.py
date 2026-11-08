# Lumen-only plugin API: things that exist on iOS and have no exteraGram equivalent.
#
#   import lumen
#   lumen.settings.set("lumen.ghost.enabled", True)        # turn ghost mode on
#   lumen.settings.set("sg.hideStories", True)             # hide stories (applies on restart)
#   lumen.settings.set("app.forceClearGlass", True)        # clear native glass in chats
#
# Keys:
#   lumen.*  Lumen's own options, changed live (ghost, saving, appearance).
#   sg.*     Swiftgram options; read live, most apply on next launch (appearance presets).
#   app.*    core app flags (native Liquid Glass).
from _lumen_bridge import native

IS_IOS = True


class _Settings(object):
    def get(self, key, default=None):
        value = native("getAppSetting", key=str(key))
        return default if value is None else value

    def set(self, key, value):
        return bool(native("setAppSetting", key=str(key), value=value))

    def toggle(self, key):
        value = not bool(self.get(key, False))
        self.set(key, value)
        return value

    def keys(self):
        return native("appSettingKeys") or []


settings = _Settings()


# Backwards-friendly shortcuts (same as the glass-only helpers used before).
def get_app_setting(key, default=None):
    return settings.get(key, default)


def set_app_setting(key, value):
    return settings.set(key, value)
