import Foundation

// MARK: Lumen

/// Buttons plugins add to the top of a profile screen (lumen.profile.add_action). The plugin
/// engine fills `actions` and installs `perform`; the profile screen reads the list and taps
/// call back into the plugin. A general extension point: no app change is needed to add a new
/// profile button.
public struct LumenProfileAction: Equatable {
    public let pluginId: String
    public let id: String
    public let title: String
    public let iconName: String?
    /// Shown only on the signed-in user's own profile.
    public let ownProfileOnly: Bool

    public init(pluginId: String, id: String, title: String, iconName: String?, ownProfileOnly: Bool) {
        self.pluginId = pluginId
        self.id = id
        self.title = title
        self.iconName = iconName
        self.ownProfileOnly = ownProfileOnly
    }
}

public enum LumenProfileActions {
    /// Updated by the plugin engine whenever a plugin adds or removes a profile button.
    public static var actions: [LumenProfileAction] = []

    /// Invoked on the main queue when a profile button is tapped. `userId` is the profile's
    /// Android-style id. Installed by the plugin engine.
    public static var perform: ((_ pluginId: String, _ id: String, _ userId: Int64) -> Void)?

    /// The buttons to show on a profile: those for everyone, plus own-only ones when it is the
    /// user's own profile.
    public static func visible(isMyProfile: Bool) -> [LumenProfileAction] {
        return self.actions.filter { isMyProfile || !$0.ownProfileOnly }
    }
}
