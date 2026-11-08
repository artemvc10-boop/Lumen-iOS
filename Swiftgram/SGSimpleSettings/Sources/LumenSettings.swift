import Foundation

/// Lumen's own options.
///
/// Kept apart from SGSimpleSettings so merging upstream Swiftgram stays simple, and read
/// straight from UserDefaults (which is thread-safe) because TelegramCore checks these
/// from its network queues, where SGSimpleSettings' unsynchronised cache is not safe.
public final class LumenSettings {
    public static let shared = LumenSettings()

    /// Posted on the main queue after any option changes.
    public static let didChangeNotification = Notification.Name("LumenSettingsDidChange")

    public enum Key: String, CaseIterable {
        /// Master switch of ghost mode; the options below choose what it hides.
        case ghostMode = "lumen.ghost.enabled"
        case ghostHideReadReceipts = "lumen.ghost.readReceipts"
        case ghostHideStoryViews = "lumen.ghost.storyViews"
        case ghostHideOnline = "lumen.ghost.online"
        case ghostHideTyping = "lumen.ghost.typing"
        /// In ghost mode, mark a chat read when you send a message to it.
        case ghostReadOnReply = "lumen.ghost.readOnReply"
        /// Keep messages other people delete, marked as deleted.
        case saveDeletedMessages = "lumen.history.deleted"
        /// Keep the earlier text of edited messages.
        case saveEditHistory = "lumen.history.edits"
        /// Turn view-once and self-destructing media into ordinary media.
        case keepViewOnceMedia = "lumen.content.viewOnce"
        /// Allow copying, forwarding and saving in chats that forbid it.
        case unlockProtectedContent = "lumen.content.unlockProtected"
        /// Allow screenshots and screen recording of protected and secret content.
        case allowScreenshots = "lumen.content.screenshots"
        /// Do not load sponsored messages in channels and bots.
        case hideSponsoredMessages = "lumen.ads.hideSponsored"
        /// Draw kept deleted and view-once messages half transparent.
        case translucentDeletedMessages = "lumen.ui.translucentDeleted"
        /// Prefix the time of kept messages with 🗑 / 🔥.
        case showRetentionMarkers = "lumen.ui.markers"
        /// The 👻 button in the chat list header.
        case ghostButtonInHeader = "lumen.ui.ghostButton"
        /// Hide the "edited" label on messages.
        case hideEditedMark = "lumen.ui.hideEdited"
        /// Install plugins that are not on the verified list.
        case allowUnverifiedPlugins = "lumen.plugins.unverified"
    }

    private static let defaultValues: [String: Any] = [
        Key.ghostMode.rawValue: false,
        Key.ghostHideReadReceipts.rawValue: true,
        Key.ghostHideStoryViews.rawValue: true,
        Key.ghostHideOnline.rawValue: true,
        Key.ghostHideTyping.rawValue: true,
        Key.ghostReadOnReply.rawValue: true,
        Key.saveDeletedMessages.rawValue: true,
        Key.saveEditHistory.rawValue: true,
        Key.keepViewOnceMedia.rawValue: true,
        Key.unlockProtectedContent.rawValue: true,
        Key.allowScreenshots.rawValue: true,
        Key.hideSponsoredMessages.rawValue: true,
        Key.translucentDeletedMessages.rawValue: true,
        Key.showRetentionMarkers.rawValue: true,
        Key.ghostButtonInHeader.rawValue: true,
        Key.hideEditedMark.rawValue: false,
        Key.allowUnverifiedPlugins.rawValue: false,
    ]

    private let store: UserDefaults

    private init() {
        self.store = .standard
        self.store.register(defaults: LumenSettings.defaultValues)
    }

    public func value(_ key: Key) -> Bool {
        return self.store.bool(forKey: key.rawValue)
    }

    public func set(_ value: Bool, for key: Key) {
        self.store.set(value, forKey: key.rawValue)
        let post = {
            NotificationCenter.default.post(name: LumenSettings.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    public var ghostMode: Bool {
        get { return self.value(.ghostMode) }
        set { self.set(newValue, for: .ghostMode) }
    }

    private func ghostHides(_ key: Key) -> Bool {
        return self.value(.ghostMode) && self.value(key)
    }

    /// Read receipts, including "listened" on voice messages and "opened" on view-once media.
    public var sendReadReceipts: Bool { return !self.ghostHides(.ghostHideReadReceipts) }
    public var sendStoryViews: Bool { return !self.ghostHides(.ghostHideStoryViews) }
    public var sendOnlineStatus: Bool { return !self.ghostHides(.ghostHideOnline) }
    public var sendTypingStatus: Bool { return !self.ghostHides(.ghostHideTyping) }
    public var readOnReply: Bool { return self.value(.ghostReadOnReply) }

    public var saveDeletedMessages: Bool { return self.value(.saveDeletedMessages) }
    public var saveEditHistory: Bool { return self.value(.saveEditHistory) }
    public var keepViewOnceMedia: Bool { return self.value(.keepViewOnceMedia) }
    public var unlockProtectedContent: Bool { return self.value(.unlockProtectedContent) }
    public var allowScreenshots: Bool { return self.value(.allowScreenshots) }
    public var hideSponsoredMessages: Bool { return self.value(.hideSponsoredMessages) }
    public var translucentDeletedMessages: Bool { return self.value(.translucentDeletedMessages) }
    public var showRetentionMarkers: Bool { return self.value(.showRetentionMarkers) }
    public var ghostButtonInHeader: Bool { return self.value(.ghostButtonInHeader) }
    public var hideEditedMark: Bool { return self.value(.hideEditedMark) }
    public var allowUnverifiedPlugins: Bool { return self.value(.allowUnverifiedPlugins) }
}
