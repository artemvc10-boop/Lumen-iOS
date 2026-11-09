import Foundation

// MARK: Lumen

/// App-level actions plugins can trigger without any native code of their own (lumen.app in
/// the plugin runtime). The UI layer installs the closures once; the plugin engine calls them.
///
/// Navigation that already works through `openUrl` (tg://user?id=, tg://resolve?domain=,
/// tg://privatepost?channel=…) is not duplicated here; these cover what a deep link cannot,
/// above all opening a conversation by its numeric id.
public enum LumenAppActions {
    /// Opens the conversation with `dialogId` (Android-style id). `messageId` (non-zero)
    /// scrolls to that message. Runs on the main queue.
    public static var openChat: ((_ dialogId: Int64, _ messageId: Int32) -> Void)?

    /// Opens a user/chat profile by its Android-style id. Runs on the main queue.
    public static var openProfile: ((_ userId: Int64) -> Void)?

    /// The conversation the user is currently looking at (Android-style id), or 0. Read on the
    /// main queue by the installer and cached; plugins read the cache.
    public static var currentChatDialogId: Int64 = 0
}
