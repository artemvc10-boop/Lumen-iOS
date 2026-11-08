import Foundation
import SGSimpleSettings

// MARK: Lumen: the settings a plugin may read and change, so customization ships as plugins
// instead of app rebuilds. Three groups:
//   lumen.*         Lumen's own options (ghost mode, saving, appearance) — live, with setters.
//   sg.<name>       Swiftgram options stored in UserDefaults (read live; write applies on the
//                   next launch for cached ones, which is enough for appearance presets).
//   app.<name>      a few core app flags wired from the app (native Liquid Glass today).

enum LumenSettingsBridge {
    /// Swiftgram options safe for plugins to change. Written straight to the shared store;
    /// most are read fresh on next launch, so a preset plugin applies on restart.
    static let swiftgramWritableKeys: Set<String> = [
        "hideTabBar", "showTabNames", "wideTabBar", "tabBarSearchEnabled",
        "compactChatList", "compactFolderNames", "hideStories", "hideReactions",
        "showProfileId", "showDC", "showRegDate", "showCreationDate",
        "secondsInMessages", "wideChannelPosts", "stickerTimestamp",
        "forceEmojiTab", "defaultEmojisFirst", "hidePhoneInSettings",
        "sendLargePhotos", "uploadSpeedBoost", "quickTranslateButton",
        "hideChannelBottomButton", "sendWithReturnKey", "videoControlsInFooter",
        "disableSnapDeletionEffect", "hideRecordingButton",
    ]

    static func allKeys() -> [String] {
        var keys = LumenSettings.Key.allCases.map { "lumen." + $0.rawValue }
        keys.append(contentsOf: self.swiftgramWritableKeys.sorted().map { "sg." + $0 })
        keys.append(contentsOf: ["app.forceClearGlass", "app.fakeGlass"])
        return keys
    }
}

extension LumenPluginManager {
    func appSettingValue(_ key: String) -> Any? {
        if key.hasPrefix("lumen."), let settingKey = LumenSettings.Key(rawValue: String(key.dropFirst("lumen.".count))) {
            return LumenSettings.shared.value(settingKey)
        }
        if key.hasPrefix("sg.") {
            return UserDefaults.standard.object(forKey: String(key.dropFirst("sg.".count)))
        }
        let appKey = key.hasPrefix("app.") ? String(key.dropFirst("app.".count)) : key
        return LumenPluginManager.appSettingReader?(appKey)
    }

    func setAppSettingValue(_ key: String, _ value: Any) -> Bool {
        if key.hasPrefix("lumen.") {
            guard let settingKey = LumenSettings.Key(rawValue: String(key.dropFirst("lumen.".count))), let flag = value as? Bool else {
                return false
            }
            LumenSettings.shared.set(flag, for: settingKey)
            return true
        }
        if key.hasPrefix("sg.") {
            let name = String(key.dropFirst("sg.".count))
            guard LumenSettingsBridge.swiftgramWritableKeys.contains(name) else {
                return false
            }
            UserDefaults.standard.set(value, forKey: name)
            NotificationCenter.default.post(name: NSNotification.Name("SGItemListUpdateNotification"), object: nil)
            return true
        }
        let appKey = key.hasPrefix("app.") ? String(key.dropFirst("app.".count)) : key
        return LumenPluginManager.appSettingWriter?(appKey, value) ?? false
    }
}
