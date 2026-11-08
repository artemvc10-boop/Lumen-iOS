# Python views of Telegram messages, shaped like the Android objects plugins expect
# (MessageObject, TLRPC.Message, TLRPC.Peer, SendMessagesHelper.SendMessageParams).
#
# Dialog ids follow the Android convention: a user is its id, a group or channel is -id.
from _lumen_java import JavaStub


class Peer(object):
    def __init__(self, dialog_id):
        self.user_id = 0
        self.chat_id = 0
        self.channel_id = 0
        if dialog_id > 0:
            self.user_id = dialog_id
        elif dialog_id < 0:
            self.channel_id = -dialog_id
            self.chat_id = -dialog_id

    def __getattr__(self, key):
        if key.startswith("__"):
            raise AttributeError(key)
        return JavaStub("TLRPC.Peer." + key)


class TLMessage(object):
    """TLRPC.Message."""

    def __init__(self, data):
        self.id = int(data.get("id", 0))
        self.message = data.get("text", "") or ""
        self.date = int(data.get("date", 0))
        self.out = bool(data.get("out", False))
        self.dialog_id = int(data.get("dialogId", 0))
        self.peer_id = Peer(self.dialog_id)
        author = data.get("authorId")
        self.from_id = Peer(int(author)) if author is not None else self.peer_id
        self.media = None
        self.entities = []
        self.reply_to = None
        self.fwd_from = None
        self.edit_date = 0
        self.mentioned = False
        self.media_unread = False
        self.silent = False
        self.post = data.get("chatType") == "channel"
        self.grouped_id = 0
        self.chat_type = data.get("chatType", "private")

    def __getattr__(self, key):
        if key.startswith("__"):
            raise AttributeError(key)
        return JavaStub("TLRPC.Message." + key)


class MessageObject(object):
    """org.telegram.messenger.MessageObject."""

    def __init__(self, data):
        self.messageOwner = TLMessage(data)
        self.messageText = self.messageOwner.message
        self.caption = None
        self.currentAccount = 0
        self.type = 0
        self._has_media = bool(data.get("hasMedia", False))

    def getId(self):
        return self.messageOwner.id

    def getDialogId(self):
        return self.messageOwner.dialog_id

    def getChatId(self):
        return -self.messageOwner.dialog_id if self.messageOwner.dialog_id < 0 else 0

    def getFromChatId(self):
        peer = self.messageOwner.from_id
        if peer.user_id:
            return peer.user_id
        return -peer.channel_id

    def getSenderId(self):
        return self.getFromChatId()

    def isOut(self):
        return self.messageOwner.out

    def isOutOwner(self):
        return self.messageOwner.out

    def isSent(self):
        return True

    def isForwarded(self):
        return False

    def isReply(self):
        return False

    def hasValidGroupId(self):
        return False

    def getGroupId(self):
        return 0

    def getDocument(self):
        return None

    def getDocumentName(self):
        return ""

    def isPhoto(self):
        return False

    def isVideo(self):
        return False

    def isGif(self):
        return False

    def isSticker(self):
        return False

    def isVoice(self):
        return False

    def isMusic(self):
        return False

    def getMessageText(self):
        return self.messageText

    def __getattr__(self, key):
        if key.startswith("__"):
            raise AttributeError(key)
        return JavaStub("MessageObject." + key)


class SendMessageParams(object):
    """SendMessagesHelper.SendMessageParams."""

    def __init__(self, data):
        self.message = data.get("text", "") or ""
        self.peer = int(data.get("dialogId", 0))
        self.caption = None
        self.entities = []
        self.replyToMsg = None
        self.replyToTopMsg = None
        self.replyQuote = None
        self.reply_to = None
        self.notify = True
        self.scheduleDate = 0
        self.schedule_date = 0
        self.searchLinks = True
        self.photo = None
        self.document = None
        self.webPage = None
        self.params = None
        self.effect_id = 0
        self.invert_media = False
        self.ttl = 0

    def __getattr__(self, key):
        if key.startswith("__"):
            raise AttributeError(key)
        return None


class Update(object):
    """TLRPC.TL_updateNewMessage / TL_updateNewChannelMessage."""

    def __init__(self, message):
        self.message = message
        self.pts = 0
        self.pts_count = 0

    def __getattr__(self, key):
        if key.startswith("__"):
            raise AttributeError(key)
        return JavaStub("TLRPC.Update." + key)
