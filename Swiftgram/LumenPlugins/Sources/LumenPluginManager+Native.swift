import Foundation
import UIKit
import ImageIO
import CryptoKit
import JavaScriptCore
import SGSimpleSettings

// MARK: Lumen: the app side of the runtime bridge. Python calls LumenNative.call(op, json)
// and gets a JSON string back, synchronously, on the plugin queue.

extension LumenPluginManager {
    func installNative(in context: JSContext) {
        let call: @convention(block) (String, String) -> String = { [weak self] op, json in
            guard let self else {
                return "null"
            }
            let arg = (LumenJSON.object(from: json) as? [String: Any]) ?? [:]
            let result = self.dispatch(op: op, arg: arg)
            return LumenJSON.string(from: result)
        }
        guard let native = JSValue(newObjectIn: context) else {
            return
        }
        native.setObject(call, forKeyedSubscript: "call" as NSString)
        context.setObject(native, forKeyedSubscript: "LumenNative" as NSString)
    }

    /// op is the bridge operation; arg carries its parameters plus "plugin" (the caller's id).
    private func dispatch(op: String, arg: [String: Any]) -> Any? {
        let pluginId = arg["plugin"] as? String ?? ""
        switch op {
        case "print", "log":
            let text = (arg["text"] as? String) ?? LumenJSON.string(from: arg["text"])
            self.appendLog(pluginId.isEmpty ? text : "[\(pluginId)] \(text)")
            return nil
        case "pluginError":
            let text = arg["text"] as? String ?? "ошибка"
            self.errors[pluginId] = text
            self.appendLog("[\(pluginId)] \(text)")
            return nil
        case "menuChanged":
            DispatchQueue.main.async { self.publish() }
            return nil
        case "setTLHooks":
            self.setTLHookInterest(arg)
            return nil
        case "tlRequest":
            self.sendTLRequest(arg)
            return nil
        case "getSetting":
            return self.settingValue(pluginId: pluginId, key: arg["key"] as? String ?? "")
        case "setSetting":
            self.setSettingValue(pluginId: pluginId, key: arg["key"] as? String ?? "", value: arg["value"])
            return nil
        case "getAllSettings":
            return self.defaults.dictionary(forKey: self.settingsKey(id: pluginId)) ?? [:]
        case "bulletin":
            self.showBulletin(arg)
            return nil
        case "alert":
            return self.showAlert(pluginId: pluginId, arg)
        case "dismissAlert":
            self.dismissAlert(arg["id"])
            return nil
        case "defer":
            self.scheduleDeferred(arg)
            return nil
        case "sleep":
            return nil
        case "fs":
            return self.handleFS(arg)
        case "zip":
            return self.handleZip(arg)
        case "http":
            return self.handleHTTP(arg)
        case "sendMessage":
            LumenHooks.sendText?(self.activeAccountPeerId, self.int64(arg["dialogId"]), arg["text"] as? String ?? "")
            return nil
        case "sendFile":
            // Plugin paths (/storage/emulated/0/...) map into the app before TelegramCore reads them.
            let raw = arg["path"] as? String ?? ""
            let path = self.mapPath(raw, pluginId: pluginId)?.path ?? raw
            LumenHooks.sendFile?(self.activeAccountPeerId, self.int64(arg["dialogId"]), path, arg["kind"] as? String ?? "document", arg["caption"] as? String ?? "")
            return nil
        case "clipboard":
            let text = arg["text"] as? String ?? ""
            DispatchQueue.main.async { UIPasteboard.general.string = text }
            return nil
        case "accountInfo":
            return LumenPluginBridgeInfo.account(self.activeAccountPeerId)
        case "hash":
            return self.handleHash(arg)
        case "uuid":
            return UUID().uuidString.lowercased()
        case "localtime", "mktime", "strftime":
            return self.handleTime(op: op, arg)
        case "themeColor":
            return LumenAndroidTheme.color(forKey: arg["key"] as? String ?? "")
        case "imageSize":
            return self.imageSize(arg["path"] as? String ?? "", pluginId: pluginId)
        case "presentView":
            self.presentAndroidView(arg)
            return nil
        case "dismissView":
            self.dismissAndroidView(arg["id"])
            return nil
        case "updateView":
            self.updateAndroidView(arg)
            return nil
        case "pickMedia":
            self.presentPicker(pluginId: pluginId, requestCode: arg["requestCode"] as? Int ?? 0, mime: arg["mime"] as? String ?? "*/*")
            return nil
        case "openUrl":
            if let text = arg["url"] as? String, let url = URL(string: text) {
                DispatchQueue.main.async { UIApplication.shared.open(url) }
            }
            return nil
        case "share":
            let paths = (arg["paths"] as? [String] ?? []).compactMap { self.mapPath($0, pluginId: pluginId) }
            self.share(urls: paths, text: arg["text"] as? String)
            return nil
        case "locale":
            let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
            return ["language": language, "country": Locale.current.regionCode ?? ""]
        case "screen":
            return LumenScreenInfo.current()
        case "getAppSetting":
            return self.appSettingValue(arg["key"] as? String ?? "") ?? NSNull()
        case "setAppSetting":
            guard let key = arg["key"] as? String, let value = arg["value"] else {
                return false
            }
            return self.setAppSettingValue(key, value)
        case "appSettingKeys":
            return LumenSettingsBridge.allKeys()
        case "presentScreen":
            self.presentScreen(pluginId: pluginId, spec: arg["spec"] as? [String: Any] ?? [:])
            return nil
        case "updateScreen":
            self.updateScreen(id: arg["id"] as? String ?? "", spec: arg["spec"] as? [String: Any] ?? [:])
            return nil
        case "dismissScreen":
            self.dismissScreen(id: arg["id"] as? String ?? "")
            return nil
        default:
            return nil
        }
    }

    private func imageSize(_ raw: String, pluginId: String) -> [String: Any] {
        guard let url = self.mapPath(raw, pluginId: pluginId), let source = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ["width": 0, "height": 0]
        }
        let width = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        return ["width": width, "height": height]
    }

    private func int64(_ value: Any?) -> Int64 {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? Double { return Int64(v) }
        if let v = value as? NSNumber { return v.int64Value }
        if let v = value as? String, let parsed = Int64(v) { return parsed }
        return 0
    }

    // MARK: Hashing

    private func handleHash(_ arg: [String: Any]) -> String {
        let algorithm = (arg["algorithm"] as? String ?? "sha256").lowercased()
        let data = Data(base64Encoded: arg["data"] as? String ?? "") ?? Data()
        func hex<T: Sequence>(_ bytes: T) -> String where T.Element == UInt8 {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        switch algorithm {
        case "md5":
            return hex(Insecure.MD5.hash(data: data))
        case "sha1":
            return hex(Insecure.SHA1.hash(data: data))
        case "sha512":
            return hex(SHA512.hash(data: data))
        default:
            return hex(SHA256.hash(data: data))
        }
    }

    // MARK: Time

    private func handleTime(op: String, _ arg: [String: Any]) -> Any? {
        var calendar = Calendar(identifier: .gregorian)
        if op == "localtime", arg["utc"] as? Bool == true {
            calendar.timeZone = TimeZone(identifier: "UTC")!
        }
        switch op {
        case "localtime":
            let seconds = (arg["t"] as? Double) ?? Date().timeIntervalSince1970
            let date = Date(timeIntervalSince1970: seconds)
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
            let weekday = ((c.weekday ?? 1) + 5) % 7 // Python: Monday = 0
            let yday = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
            return [c.year ?? 1970, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, weekday, yday, 0]
        case "mktime":
            let parts = (arg["parts"] as? [Int]) ?? []
            var components = DateComponents()
            if parts.count >= 6 {
                components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
                components.hour = parts[3]; components.minute = parts[4]; components.second = parts[5]
            }
            return (calendar.date(from: components)?.timeIntervalSince1970) ?? 0
        case "strftime":
            let seconds = (arg["t"] as? Double) ?? Date().timeIntervalSince1970
            return LumenStrftime.format(arg["format"] as? String ?? "", date: Date(timeIntervalSince1970: seconds))
        default:
            return nil
        }
    }

    // MARK: Native plugins

    func registerNativePlugins() {
        for id in LumenPluginManager.nativePluginIds where self.enabledIds().contains(id) {
            if self.nativeHandlers[id] == nil, let handler = LumenNativeRegistry.make(id: id) {
                self.nativeHandlers[id] = handler
            }
        }
    }
}

enum LumenPluginBridgeInfo {
    /// Set by the app so plugins can read the current account. Kept here to avoid a
    /// TelegramCore dependency inside the engine module.
    public static var accountProvider: ((Int64) -> [String: Any])?

    static func account(_ peerId: Int64) -> [String: Any] {
        return accountProvider?(peerId) ?? ["userId": peerId]
    }
}

/// Native plugin factory, filled by the modules that implement them (the meme library).
public enum LumenNativeRegistry {
    public static var factories: [String: () -> LumenNativePlugin] = [:]

    static func make(id: String) -> LumenNativePlugin? {
        return factories[id]?()
    }
}

enum LumenStrftime {
    static func format(_ format: String, date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?) -> String {
            return String(format: "%02d", value ?? 0)
        }
        var result = ""
        var iterator = format.makeIterator()
        while let char = iterator.next() {
            if char != "%" {
                result.append(char)
                continue
            }
            guard let spec = iterator.next() else {
                break
            }
            switch spec {
            case "Y": result += String(c.year ?? 1970)
            case "m": result += pad(c.month)
            case "d": result += pad(c.day)
            case "H": result += pad(c.hour)
            case "M": result += pad(c.minute)
            case "S": result += pad(c.second)
            case "%": result += "%"
            default: result += "%\(spec)"
            }
        }
        return result
    }
}
