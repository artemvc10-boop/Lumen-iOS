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
    }

    private static let defaultValues: [String: Any] = [
        Key.ghostMode.rawValue: false,
        Key.ghostHideReadReceipts.rawValue: true,
        Key.ghostHideStoryViews.rawValue: true,
        Key.ghostHideOnline.rawValue: true,
        Key.ghostHideTyping.rawValue: true,
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
}
