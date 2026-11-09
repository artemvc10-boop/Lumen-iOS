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

    // MARK: Raw TL hooks (exteraGram's pre_request_hook / post_request_hook / on_update_hook)

    /// Names plugins subscribed to, in Android form (`TL_messages_sendMessage`,
    /// `TL_updateUserTyping`). TelegramCore checks it before converting anything, so with no
    /// subscriptions the hooks cost one lock per request.
    public static let tlHookFilter = LumenTLHookFilter()

    /// Before a request is sent. `json` is the call (see LumenTLJSON). The completion may run
    /// on any queue and must be called exactly once.
    public static var preRequest: ((_ accountPeerId: Int64, _ name: String, _ json: String, _ completion: @escaping (LumenTLHookDecision) -> Void) -> Void)?

    /// After a response or error arrives. `json` is `{"result": ...}`, nil on error.
    public static var postRequest: ((_ accountPeerId: Int64, _ name: String, _ json: String?, _ errorCode: Int32, _ errorText: String?, _ completion: @escaping (LumenTLHookDecision) -> Void) -> Void)?

    /// Sends a plugin's own request (`{"_": "messages.getHistory", ...}`). The completion
    /// gets `{"result": ...}` as JSON, or nil with the error. Installed by TelegramCore.
    public static var sendTLRequest: ((_ accountPeerId: Int64, _ json: String, _ completion: @escaping (_ result: String?, _ errorCode: Int32, _ errorText: String?) -> Void) -> Void)?

    /// For each update before it is applied. Called synchronously on the account's state
    /// queue; implementations must answer quickly (the engine gives up after a short wait).
    public static var update: ((_ accountPeerId: Int64, _ name: String, _ json: String) -> LumenTLHookDecision)?
}

public enum LumenTLHookDecision {
    case keep
    case cancel
    /// The replacement object, as JSON.
    case replace(String)
    /// Post-request only: turn the response into this error.
    case error(code: Int32, text: String)
}

/// Thread-safe set of hooked names: exact names and substrings.
public final class LumenTLHookFilter {
    private let lock = NSLock()
    private var exact: Set<String> = []
    private var substrings: [String] = []
    private var cache: [String: Bool] = [:]

    public init() {
    }

    public var isEmpty: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.exact.isEmpty && self.substrings.isEmpty
    }

    public func set(exact: Set<String>, substrings: [String]) {
        self.lock.lock()
        self.exact = exact
        self.substrings = substrings.filter { !$0.isEmpty }
        self.cache = [:]
        self.lock.unlock()
    }

    public func matches(_ name: String) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.exact.isEmpty && self.substrings.isEmpty {
            return false
        }
        if let cached = self.cache[name] {
            return cached
        }
        let result = self.exact.contains(name) || self.substrings.contains(where: { name.contains($0) })
        if self.cache.count > 4096 {
            self.cache = [:]
        }
        self.cache[name] = result
        return result
    }
}

/// `messages.sendMessage` → `TL_messages_sendMessage`, as the Android class is named.
public func lumenAndroidTLName(_ name: String) -> String {
    return "TL_" + name.replacingOccurrences(of: ".", with: "_")
}
