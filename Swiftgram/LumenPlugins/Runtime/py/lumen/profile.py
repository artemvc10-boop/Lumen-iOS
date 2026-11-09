# Profile and chat decorations rendered natively by Lumen.
#
#   from lumen import profile
#   profile.set(user_id, {
#       "banner": {"type": "gradient", "colors": ["#FF5E62", "#FF9966"], "angle": 90, "fade": 0.3},
#       "background": {"type": "image", "image": "/path/bg.jpg", "dim": 0.3},
#       "avatar": {"shape": 1, "radius": 18},      # 0 circle 1 rounded 2 square 3 hex 4 penta 5 star 6 heart
#       "name": {"color": "#FFD700", "glow": {"color": "#FFAA00", "radius": 10}},
#       "colors": {"text": "#FFFFFF", "hint": "#BBBBBB", "action": "#FFD700", "blocks": "#66000000"},
#       "thought": {"text": "hi", "color": "#FFFFFF", "background": "#80000000"},
#       "sound": {"path": "/path/intro.m4a", "volume": 0.6},
#       "chat": {"nameColor": "#FFD700", "ring": {"colors": ["#FFD700"], "width": 2}, "tag": {"text": "[CLAN]", "color": "#00FF00"}},
#   })
#
# Plugins hear which decorations to load through BasePlugin.on_profile_open(user_id) and
# on_chat_users(user_ids). user_id is the Android-style dialog id.
from _lumen_bridge import native


def set(user_id, spec):
    native("decorationSet", userId=int(user_id), spec=spec)


def clear(user_id=None):
    if user_id is None:
        native("decorationClear", all=True)
    else:
        native("decorationClear", userId=int(user_id))
