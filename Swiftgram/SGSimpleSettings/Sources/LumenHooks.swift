import Foundation

// MARK: Lumen

/// An incoming message as plugins see it. Ids are Telegram's 64-bit peer ids
/// (`PeerId.toInt64()`), so they round-trip through JavaScript unchanged.
public struct LumenIncomingMessage {
    public let accountPeerId: Int64
    public let peerId: Int64
    public let authorId: Int64?
    public let messageId: Int32
    public let text: String
    /// "private", "group", "channel" or "secret".
    public let chatType: String

    public init(accountPeerId: Int64, peerId: Int64, authorId: Int64?, messageId: Int32, text: String, chatType: String) {
        self.accountPeerId = accountPeerId
        self.peerId = peerId
        self.authorId = authorId
        self.messageId = messageId
        self.text = text
        self.chatType = chatType
    }
}

/// Connection points between TelegramCore and the plugin engine.
///
/// TelegramCore cannot depend on the engine (the engine sits above it), so both sides meet
/// here: the engine installs the transform and observer, TelegramCore installs `sendText`.
/// Each is assigned once at startup.
public enum LumenHooks {
    /// Called for the text of every outgoing message. Return the text to send, or nil to
    /// cancel the message.
    public static var transformOutgoingText: ((_ accountPeerId: Int64, _ peerId: Int64, _ text: String) -> String?)?

    /// Called, never on the main queue, with messages that just arrived.
    public static var incomingMessages: (([LumenIncomingMessage]) -> Void)?

    /// Sends a text message from the given account. Installed by TelegramCore.
    public static var sendText: ((_ accountPeerId: Int64, _ peerId: Int64, _ text: String) -> Void)?
}
