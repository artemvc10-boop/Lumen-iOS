# App actions for plugins. Navigation that a tg:// link already covers is reached through
# open_url; the rest (opening a conversation by its numeric id, the current chat) is here.
#
#   from lumen import app
#   app.open_chat(user_id)              # open the conversation (dialog id: user = id, chat = -id)
#   app.open_chat(chat_id, message_id)  # ...scrolled to a message
#   app.open_profile(user_id)           # open a profile
#   app.open_url("tg://resolve?domain=durov")
#   where = app.current_chat()          # dialog id of the chat on screen, or 0
from _lumen_bridge import native


def open_chat(dialog_id, message_id=0):
    native("openChat", dialogId=int(dialog_id), messageId=int(message_id or 0))


def open_profile(user_id):
    native("openProfile", userId=int(user_id))


def open_url(url):
    native("openUrl", url=str(url))


def current_chat():
    result = native("currentChat") or {}
    return int(result.get("dialogId", 0) or 0)


def download_media(dialog_id, message_id, callback):
    """Download a message's photo/video/file; callback(path) gets a local path or None."""
    import _lumen_host
    cb = _lumen_host.register_callback(lambda result: callback((result or {}).get("path")))
    native("downloadMessageMedia", sourceDialogId=int(dialog_id), sourceMessageId=int(message_id), callback=cb)
