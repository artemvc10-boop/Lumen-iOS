# Raw TL access for plugins (Lumen name for what exteraGram exposes through TLRPC):
#
#   from lumen import tl
#   req = tl.new("messages.getHistory", peer=tl.new("inputPeerSelf"), limit=10,
#                offset_id=0, offset_date=0, add_offset=0, max_id=0, min_id=0, hash=0)
#   tl.send(req, lambda response, error: ...)
#
# Hooks use the Android names: self.add_hook("TL_messages_setTyping"), then
# pre_request_hook / post_request_hook / on_update_hook as in exteraGram.
from _lumen_tl import TLObject, TLRPC, TL_error, new, from_json, to_json, android_name, schema_name


def send(request, callback=None):
    import client_utils
    return client_utils.send_request(request, callback)
