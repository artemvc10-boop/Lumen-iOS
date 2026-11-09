# exteraGram client_utils: messaging and threading helpers.
from _lumen_bridge import native, log as _log
from _lumen_java import JavaStub

CACHE_CLEAR_QUEUE = "cacheClearQueue"
EXTERNAL_NETWORK_QUEUE = "externalNetworkQueue"
GLOBAL_QUEUE = "globalQueue"
PHONE_BOOK_QUEUE = "phoneBookQueue"
PLUGINS_QUEUE = "pluginsQueue"
SEARCH_QUEUE = "searchQueue"
STAGE_QUEUE = "stageQueue"
THEME_QUEUE = "themeQueue"


def _peer_of(value):
    try:
        return int(value)
    except Exception:
        return 0


def _text_of(params):
    text = params.get("message")
    if text is None:
        text = params.get("caption")
    if text is None:
        text = params.get("text")
    return "" if text is None else str(text)


def send_message(params, *args, **kwargs):
    """send_message({"peer": dialog_id, "message": "text", ...})."""
    if not isinstance(params, dict):
        peer = getattr(params, "peer", 0)
        text = getattr(params, "message", "") or ""
        native("sendMessage", dialogId=_peer_of(peer), text=str(text))
        return
    native("sendMessage", dialogId=_peer_of(params.get("peer", 0)), text=_text_of(params))


def send_text(peer_id, text, *args, **kwargs):
    native("sendMessage", dialogId=_peer_of(peer_id), text=str(text))


def _send_file(kind, peer, path, caption):
    native("sendFile", dialogId=_peer_of(peer), path=str(path), kind=kind, caption="" if caption is None else str(caption))


def send_photo(peer, path, caption=None, *args, **kwargs):
    _send_file("photo", peer, path, caption)


def send_document(peer, path, caption=None, *args, **kwargs):
    _send_file("document", peer, path, caption)


def send_video(peer, path, caption=None, *args, **kwargs):
    _send_file("video", peer, path, caption)


def send_audio(peer, path, caption=None, *args, **kwargs):
    _send_file("document", peer, path, caption)


def edit_message(peer, message_id, text, callback=None, *args, **kwargs):
    """Edit a text message. peer is an Android-style dialog id; message_id the cloud id."""
    import _lumen_tl
    peer_id = _peer_of(peer)
    if peer_id > 0:
        input_peer = _lumen_tl.new("inputPeerUser", user_id=peer_id, access_hash=0)
    elif peer_id < 0:
        input_peer = _lumen_tl.new("inputPeerChannel", channel_id=-peer_id, access_hash=0)
    else:
        input_peer = _lumen_tl.new("inputPeerSelf")
    req = _lumen_tl.new("messages.editMessage", peer=input_peer, id=int(message_id), message=str(text))
    return send_request(req, callback)


def send_request(request, callback=None, *args, **kwargs):
    """Sends any TL request; callback(response, error) like Android's RequestDelegate.

    `request` is a TLObject (TLRPC.TL_messages_getHistory(...), lumen.tl.new(...)) or a dict
    in the app's JSON form. The callback may also be an object with `run(response, error)`.
    """
    import _lumen_tl
    import _lumen_host
    from _lumen_bridge import native
    payload = request if isinstance(request, dict) else _lumen_tl.to_json(request)
    callback_id = None
    if callback is not None:
        target = callback if callable(callback) else getattr(callback, "run", None)

        def deliver(response, error):
            if target is None:
                return
            value = _lumen_tl.from_json(response) if response is not None else None
            failure = None
            if error is not None:
                failure = _lumen_tl.TL_error(error.get("code", 0), error.get("text", ""))
            target(value, failure)

        callback_id = _lumen_host.register_callback(deliver)
    native("tlRequest", request=payload, callback=callback_id)
    return callback_id or 0


def run_on_ui_thread(fn, delay=0, *args, **kwargs):
    import _lumen_host
    _lumen_host.defer(fn, delay)


def run_on_queue(fn, queue_name=PLUGINS_QUEUE, delay=0, *args, **kwargs):
    import _lumen_host
    _lumen_host.defer(fn, delay)


def get_queue_by_name(name):
    return JavaStub("DispatchQueue")


def get_last_fragment():
    import _lumen_activity
    return _lumen_activity.current_fragment()


def get_selected_account():
    return 0


class _UserConfig(object):
    def getClientUserId(self):
        info = native("accountInfo") or {}
        return int(info.get("userId", 0))

    def isClientActivated(self):
        return True

    def getCurrentUser(self):
        info = native("accountInfo") or {}
        return _CurrentUser(info)

    def __getattr__(self, key):
        if key.startswith("__"):
            raise AttributeError(key)
        return JavaStub("UserConfig." + key)


class _CurrentUser(object):
    def __init__(self, info):
        self.id = int(info.get("userId", 0))
        self.first_name = info.get("firstName", "")
        self.last_name = info.get("lastName", "")
        self.username = info.get("username", "")
        self.phone = ""

    def __getattr__(self, key):
        if key.startswith("__"):
            raise AttributeError(key)
        return JavaStub("TLRPC.User." + key)


def get_user_config(*args, **kwargs):
    return _UserConfig()


def _stub(name):
    def get(*args, **kwargs):
        return JavaStub(name)
    return get


get_account_instance = _stub("AccountInstance")
get_messages_controller = _stub("MessagesController")
get_messages_storage = _stub("MessagesStorage")
get_contacts_controller = _stub("ContactsController")
get_connections_manager = _stub("ConnectionsManager")
get_media_data_controller = _stub("MediaDataController")
get_media_controller = _stub("MediaController")
get_file_loader = _stub("FileLoader")
get_download_controller = _stub("DownloadController")
get_location_controller = _stub("LocationController")
get_notification_center = _stub("NotificationCenter")
get_notifications_controller = _stub("NotificationsController")
get_notifications_settings = _stub("SharedPreferences")
get_secret_chat_helper = _stub("SecretChatHelper")
get_send_messages_helper = _stub("SendMessagesHelper")
