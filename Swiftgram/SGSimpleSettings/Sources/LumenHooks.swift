import Foundation

// MARK: Lumen

/// An incoming message as plugins see it.
///
/// `peerId` is Telegram's 64-bit peer id (`PeerId.toInt64()`); `dialogId` is the same chat
/// in the Android client's convention, which exteraGram plugins use: a user is its id, a
/// group or channel is minus its id.
public struct LumenIncomingMessage {
    public let accountPeerId: Int64
    public let peerId: Int64
    public let dialogId: Int64
    public let authorId: Int64?
    public let messageId: Int32
    public let date: Int32
    public let text: String
    /// "private", "group", "channel" or "secret".
    public let chatType: String
    /// The chat is a channel or supergroup (TL_updateNewChannelMessage on Android).
    public let isChannel: Bool
    public let isOutgoing: Bool

    public init(accountPeerId: Int64, peerId: Int64, dialogId: Int64, authorId: Int64?, messageId: Int32, date: Int32, text: String, chatType: String, isChannel: Bool, isOutgoing: Bool) {
        self.accountPeerId = accountPeerId
        self.peerId = peerId
        self.dialogId = dialogId
        self.authorId = authorId
        self.messageId = messageId
        self.date = date
        self.text = text
        self.chatType = chatType
        self.isChannel = isChannel
        self.isOutgoing = isOutgoing
    }
}

/// Connection points between TelegramCore and the plugin engine.
///
/// TelegramCore cannot depend on the engine (the engine sits above it), so both sides meet
/// here: the engine installs the transform and observer, TelegramCore installs the senders.
/// Each is assigned once at startup.
public enum LumenHooks {
    /// Called for the text of every outgoing message. Return the text to send, or nil to
    /// cancel the message.
    public static var transformOutgoingText: ((_ accountPeerId: Int64, _ dialogId: Int64, _ text: String) -> String?)?

    /// Called, never on the main queue, with messages that just arrived.
    public static var incomingMessages: (([LumenIncomingMessage]) -> Void)?

    /// Sends a text message from the given account to an Android-style dialog id.
    /// Installed by TelegramCore.
    public static var sendText: ((_ accountPeerId: Int64, _ dialogId: Int64, _ text: String) -> Void)?

    /// Sends a local file: kind is "photo", "video" or "document". Installed by TelegramCore.
    public static var sendFile: ((_ accountPeerId: Int64, _ dialogId: Int64, _ path: String, _ kind: String, _ caption: String) -> Void)?
}
