import Foundation
import UIKit
import Combine
import JavaScriptCore
import SGSimpleSettings

// MARK: Lumen plugins
//
// Plugins are JavaScript files run by JavaScriptCore, one JSContext per plugin, all on a
// single serial queue (JSContext is not thread-safe). A plugin calls Lumen.register({...})
// with its description and hooks; see docs/PLUGINS.md for the API.
//
// Telegram ids are passed to JavaScript as strings: they are 64-bit and JavaScript numbers
// lose precision above 2^53.

public struct LumenPluginSetting: Identifiable, Equatable {
    public enum Kind: Equatable {
        case toggle(defaultValue: Bool)
        case text(defaultValue: String)
    }

    public let key: String
    public let title: String
    public let kind: Kind

    public var id: String { return self.key }
}

public struct LumenPluginInfo: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let author: String
    public let version: String
    public let description: String
    public let settings: [LumenPluginSetting]
    public let isEnabled: Bool
    public let error: String?
}

public struct LumenPluginMenuItem: Equatable {
    public let pluginId: String
    public let index: Int
    public let title: String
}

/// What a message menu action receives about the message it was opened on.
public struct LumenPluginMessageContext {
    public let accountPeerId: Int64
    public let peerId: Int64
    public let messageId: Int32
    public let text: String

    public init(accountPeerId: Int64, peerId: Int64, messageId: Int32, text: String) {
        self.accountPeerId = accountPeerId
        self.peerId = peerId
        self.messageId = messageId
        self.text = text
    }
}

private final class LoadedPlugin {
    let id: String
    let context: JSContext
    var definition: JSValue?

    init(id: String, context: JSContext) {
        self.id = id
        self.context = context
    }
}

public final class LumenPluginManager: ObservableObject {
    public static let shared = LumenPluginManager()

    /// Published on the main queue for the plugins screen.
    @Published public private(set) var plugins: [LumenPluginInfo] = []
    @Published public private(set) var log: [String] = []

    private let queue = DispatchQueue(label: "lumen.plugins")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var loaded: [String: LoadedPlugin] = [:]
    private var errors: [String: String] = [:]
    private var logLines: [String] = []
    private var started = false

    private let menuItemsLock = NSLock()
    private var currentMenuItems: [LumenPluginMenuItem] = []

    /// Account of the last hook call; Lumen.sendMessage sends from it.
    private var activeAccountPeerId: Int64?

    private let defaults = UserDefaults.standard
    private static let enabledKey = "lumen.plugins.enabled"

    public let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LumenPlugins", isDirectory: true)
    }()

    private init() {
        self.queue.setSpecific(key: self.queueKey, value: true)
    }

    // MARK: Queue

    /// Runs on the plugin queue, inline when already on it so a plugin calling back into
    /// the app (Lumen.sendMessage -> outgoing hook) cannot deadlock.
    private func sync<T>(_ f: () -> T) -> T {
        if DispatchQueue.getSpecific(key: self.queueKey) == true {
            return f()
        }
        return self.queue.sync(execute: f)
    }

    // MARK: Startup

    /// Installs the hooks and loads the enabled plugins. Safe to call more than once.
    public func start() {
        self.queue.async {
            if self.started {
                return
            }
            self.started = true
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            self.installSamplesIfNeeded()

            LumenHooks.transformOutgoingText = { [weak self] accountPeerId, peerId, text in
                guard let self else {
                    return text
                }
                return self.sync {
                    self.transformOutgoing(accountPeerId: accountPeerId, peerId: peerId, text: text)
                }
            }
            LumenHooks.incomingMessages = { [weak self] messages in
                self?.queue.async {
                    self?.deliverIncoming(messages)
                }
            }

            for id in self.enabledIds() {
                self.load(id: id)
            }
            self.publish()
        }
    }

    // MARK: Files

    private func fileURL(id: String) -> URL {
        return self.directory.appendingPathComponent(id + ".js")
    }

    private func allIds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "js" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    private func enabledIds() -> [String] {
        return self.defaults.stringArray(forKey: LumenPluginManager.enabledKey) ?? []
    }

    private func setEnabledIds(_ ids: [String]) {
        self.defaults.set(Array(Set(ids)).sorted(), forKey: LumenPluginManager.enabledKey)
    }

    private static func sanitizedId(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let base = (name as NSString).deletingPathExtension
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "plugin" : cleaned
    }

    /// Copies a .js file into the plugins folder. The plugin starts disabled.
    public func install(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            self.queue.async {
                self.appendLog("Не удалось прочитать \(url.lastPathComponent)")
                self.publish()
            }
            return
        }
        let id = LumenPluginManager.sanitizedId(url.lastPathComponent)
        self.queue.async {
            if self.loaded[id] != nil {
                self.unload(id: id)
            }
            do {
                try source.write(to: self.fileURL(id: id), atomically: true, encoding: .utf8)
                self.appendLog("Установлен плагин \(id)")
                if self.enabledIds().contains(id) {
                    self.load(id: id)
                }
            } catch {
                self.appendLog("Не удалось сохранить \(id): \(error.localizedDescription)")
            }
            self.publish()
        }
    }

    public func remove(id: String) {
        self.queue.async {
            self.unload(id: id)
            try? FileManager.default.removeItem(at: self.fileURL(id: id))
            self.setEnabledIds(self.enabledIds().filter { $0 != id })
            self.defaults.removeObject(forKey: self.settingsKey(id: id))
            self.defaults.removeObject(forKey: self.storageKey(id: id))
            self.errors[id] = nil
            self.publish()
        }
    }

    public func setEnabled(id: String, enabled: Bool) {
        self.queue.async {
            var ids = self.enabledIds().filter { $0 != id }
            if enabled {
                ids.append(id)
            }
            self.setEnabledIds(ids)
            if enabled {
                self.load(id: id)
            } else {
                self.unload(id: id)
            }
            self.publish()
        }
    }

    // MARK: Loading

    private func load(id: String) {
        if self.loaded[id] != nil {
            return
        }
        guard let source = try? String(contentsOf: self.fileURL(id: id), encoding: .utf8) else {
            self.errors[id] = "Файл не найден"
            return
        }
        guard let context = JSContext() else {
            self.errors[id] = "Не удалось создать JSContext"
            return
        }
        context.name = "Lumen plugin \(id)"
        let plugin = LoadedPlugin(id: id, context: context)
        self.errors[id] = nil
        context.exceptionHandler = { [weak self] _, exception in
            let message = exception?.toString() ?? "unknown error"
            self?.errors[id] = message
            self?.appendLog("[\(id)] ошибка: \(message)")
        }
        self.installAPI(in: context, plugin: plugin)
        self.loaded[id] = plugin
        context.evaluateScript(source, withSourceURL: self.fileURL(id: id))
        if plugin.definition == nil {
            self.errors[id] = self.errors[id] ?? "Плагин не вызвал Lumen.register({...})"
        } else {
            self.call(plugin, "onLoad", [])
        }
        self.updateMenuItems()
    }

    private func unload(id: String) {
        guard let plugin = self.loaded[id] else {
            return
        }
        self.call(plugin, "onUnload", [])
        self.loaded[id] = nil
        self.updateMenuItems()
    }

    // MARK: JavaScript API

    private func settingsKey(id: String) -> String {
        return "lumen.plugins.\(id).settings"
    }

    private func storageKey(id: String) -> String {
        return "lumen.plugins.\(id).storage"
    }

    private func installAPI(in context: JSContext, plugin: LoadedPlugin) {
        let id = plugin.id
        guard let lumen = JSValue(newObjectIn: context) else {
            return
        }

        let register: @convention(block) (JSValue) -> Void = { [weak plugin] definition in
            plugin?.definition = definition
        }
        let log: @convention(block) (JSValue) -> Void = { [weak self] value in
            self?.appendLog("[\(id)] \(value.toString() ?? "")")
            self?.publishSoon()
        }
        let storageGet: @convention(block) (String) -> JSValue = { [weak self] key in
            let stored: Any? = (self?.defaults.dictionary(forKey: self?.storageKey(id: id) ?? "") ?? [:])[key]
            let value: Any = stored ?? NSNull()
            return JSValue(object: value, in: JSContext.current())
        }
        let storageSet: @convention(block) (String, JSValue) -> Void = { [weak self] key, value in
            guard let self else {
                return
            }
            var stored = self.defaults.dictionary(forKey: self.storageKey(id: id)) ?? [:]
            if value.isUndefined || value.isNull {
                stored[key] = nil
            } else if value.isBoolean {
                stored[key] = value.toBool()
            } else if value.isNumber {
                stored[key] = value.toDouble()
            } else {
                stored[key] = value.toString()
            }
            self.defaults.set(stored, forKey: self.storageKey(id: id))
        }
        let setting: @convention(block) (String) -> JSValue = { [weak self] key in
            guard let self else {
                return JSValue(undefinedIn: JSContext.current())
            }
            let value: Any = self.settingValue(id: id, key: key) ?? NSNull()
            return JSValue(object: value, in: JSContext.current())
        }
        let sendMessage: @convention(block) (String, String) -> Void = { [weak self] peerId, text in
            guard let self, let peer = Int64(peerId), let account = self.activeAccountPeerId else {
                self?.appendLog("[\(id)] sendMessage: нет активного аккаунта или неверный peerId")
                return
            }
            LumenHooks.sendText?(account, peer, text)
        }
        let fetch: @convention(block) (String, JSValue, JSValue) -> Void = { [weak self] urlString, options, callback in
            self?.performFetch(urlString: urlString, options: options, callback: callback, pluginId: id)
        }

        lumen.setObject(register, forKeyedSubscript: "register" as NSString)
        lumen.setObject(log, forKeyedSubscript: "log" as NSString)
        lumen.setObject(setting, forKeyedSubscript: "setting" as NSString)
        lumen.setObject(sendMessage, forKeyedSubscript: "sendMessage" as NSString)
        lumen.setObject(fetch, forKeyedSubscript: "fetch" as NSString)
        let alert: @convention(block) (String, JSValue) -> Void = { title, text in
            let message = (text.isUndefined || text.isNull) ? nil : text.toString()
            DispatchQueue.main.async {
                LumenPluginManager.presentAlert(title: title, message: message)
            }
        }
        lumen.setObject(alert, forKeyedSubscript: "alert" as NSString)
        lumen.setObject("1", forKeyedSubscript: "apiVersion" as NSString)
        if let storage = JSValue(newObjectIn: context) {
            storage.setObject(storageGet, forKeyedSubscript: "get" as NSString)
            storage.setObject(storageSet, forKeyedSubscript: "set" as NSString)
            lumen.setObject(storage, forKeyedSubscript: "storage" as NSString)
        }
        context.setObject(lumen, forKeyedSubscript: "Lumen" as NSString)
        // console.log for code copied from elsewhere.
        if let console = JSValue(newObjectIn: context) {
            console.setObject(log, forKeyedSubscript: "log" as NSString)
            console.setObject(log, forKeyedSubscript: "error" as NSString)
            context.setObject(console, forKeyedSubscript: "console" as NSString)
        }
    }

    private func performFetch(urlString: String, options: JSValue, callback: JSValue, pluginId: String) {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            callback.call(withArguments: ["invalid url", NSNull(), 0])
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 20.0)
        if options.isObject {
            if let method = options.forProperty("method"), method.isString {
                request.httpMethod = method.toString()
            }
            if let body = options.forProperty("body"), body.isString {
                request.httpBody = body.toString()?.data(using: .utf8)
            }
            if let headers = options.forProperty("headers")?.toDictionary() as? [String: Any] {
                for (key, value) in headers {
                    request.setValue("\(value)", forHTTPHeaderField: key)
                }
            }
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.queue.async {
                // The plugin may have been unloaded meanwhile; its context is then gone.
                guard self?.loaded[pluginId] != nil else {
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.flatMap { String(data: $0, encoding: .utf8) }
                let errorValue: Any = error.map { $0.localizedDescription } ?? NSNull()
                let bodyValue: Any = body.map { $0 as Any } ?? NSNull()
                callback.call(withArguments: [errorValue, bodyValue, status])
            }
        }.resume()
    }

    @discardableResult
    private func call(_ plugin: LoadedPlugin, _ name: String, _ arguments: [Any]) -> JSValue? {
        guard let function = plugin.definition?.forProperty(name), !function.isUndefined, !function.isNull else {
            return nil
        }
        return function.call(withArguments: arguments)
    }

    // MARK: Hooks

    private func transformOutgoing(accountPeerId: Int64, peerId: Int64, text: String) -> String? {
        self.activeAccountPeerId = accountPeerId
        var current = text
        for id in self.loaded.keys.sorted() {
            guard let plugin = self.loaded[id] else {
                continue
            }
            let message: [String: Any] = ["text": current, "peerId": String(peerId)]
            guard let result = self.call(plugin, "onSendMessage", [message]) else {
                continue
            }
            if result.isBoolean && !result.toBool() {
                self.appendLog("[\(id)] отменил отправку")
                self.publishSoon()
                return nil
            }
            if result.isString, let updated = result.toString() {
                current = updated
            }
        }
        return current
    }

    private func deliverIncoming(_ messages: [LumenIncomingMessage]) {
        guard !self.loaded.isEmpty else {
            return
        }
        for message in messages {
            self.activeAccountPeerId = message.accountPeerId
            for id in self.loaded.keys.sorted() {
                guard let plugin = self.loaded[id] else {
                    continue
                }
                let payload = self.messageObject(in: plugin.context, accountPeerId: message.accountPeerId, peerId: message.peerId, messageId: message.messageId, text: message.text, authorId: message.authorId)
                self.call(plugin, "onIncomingMessage", [payload])
            }
        }
    }

    private func messageObject(in context: JSContext, accountPeerId: Int64, peerId: Int64, messageId: Int32, text: String, authorId: Int64?) -> JSValue {
        let object = JSValue(newObjectIn: context)!
        object.setObject(text, forKeyedSubscript: "text" as NSString)
        object.setObject(String(peerId), forKeyedSubscript: "peerId" as NSString)
        object.setObject(Int(messageId), forKeyedSubscript: "messageId" as NSString)
        let authorValue: Any = authorId.map { String($0) as Any } ?? NSNull()
        object.setObject(authorValue, forKeyedSubscript: "authorId" as NSString)
        let reply: @convention(block) (String) -> Void = { replyText in
            LumenHooks.sendText?(accountPeerId, peerId, replyText)
        }
        object.setObject(reply, forKeyedSubscript: "reply" as NSString)
        return object
    }

    // MARK: Alerts

    private static func presentAlert(title: String, message: String?) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard var top = (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.rootViewController else {
            return
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .cancel))
        top.present(controller, animated: true)
    }

    // MARK: Message menu

    /// Items plugins added to the message menu. Safe from any thread.
    public func messageMenuItems() -> [LumenPluginMenuItem] {
        self.menuItemsLock.lock()
        defer {
            self.menuItemsLock.unlock()
        }
        return self.currentMenuItems
    }

    public func performMenuItem(_ item: LumenPluginMenuItem, message: LumenPluginMessageContext) {
        self.queue.async {
            guard let plugin = self.loaded[item.pluginId], let items = plugin.definition?.forProperty("menuItems"), items.isObject else {
                return
            }
            guard let entry = items.atIndex(item.index), let onClick = entry.forProperty("onClick"), !onClick.isUndefined else {
                return
            }
            self.activeAccountPeerId = message.accountPeerId
            let payload = self.messageObject(in: plugin.context, accountPeerId: message.accountPeerId, peerId: message.peerId, messageId: message.messageId, text: message.text, authorId: nil)
            onClick.call(withArguments: [payload])
            self.publishSoon()
        }
    }

    private func updateMenuItems() {
        var result: [LumenPluginMenuItem] = []
        for id in self.loaded.keys.sorted() {
            guard let items = self.loaded[id]?.definition?.forProperty("menuItems"), items.isObject else {
                continue
            }
            let count = Int(items.forProperty("length")?.toInt32() ?? 0)
            for index in 0 ..< count {
                if let title = items.atIndex(index)?.forProperty("title"), title.isString, let text = title.toString() {
                    result.append(LumenPluginMenuItem(pluginId: id, index: index, title: text))
                }
            }
        }
        self.menuItemsLock.lock()
        self.currentMenuItems = result
        self.menuItemsLock.unlock()
    }

    // MARK: Settings

    public func settingValue(id: String, key: String) -> Any? {
        if let stored = self.defaults.dictionary(forKey: self.settingsKey(id: id))?[key] {
            return stored
        }
        for setting in self.parseSettings(id: id) where setting.key == key {
            switch setting.kind {
            case let .toggle(defaultValue):
                return defaultValue
            case let .text(defaultValue):
                return defaultValue
            }
        }
        return nil
    }

    public func setSettingValue(id: String, key: String, value: Any) {
        self.queue.async {
            var stored = self.defaults.dictionary(forKey: self.settingsKey(id: id)) ?? [:]
            stored[key] = value
            self.defaults.set(stored, forKey: self.settingsKey(id: id))
            if let plugin = self.loaded[id] {
                self.call(plugin, "onSettingChanged", [key, value])
            }
            self.publish()
        }
    }

    private func parseSettings(id: String) -> [LumenPluginSetting] {
        guard let items = self.loaded[id]?.definition?.forProperty("settings"), items.isObject else {
            return []
        }
        var result: [LumenPluginSetting] = []
        let count = Int(items.forProperty("length")?.toInt32() ?? 0)
        for index in 0 ..< count {
            guard let item = items.atIndex(index), let key = item.forProperty("key")?.toString(), let title = item.forProperty("title")?.toString() else {
                continue
            }
            let type = item.forProperty("type")?.toString() ?? "switch"
            let defaultValue = item.forProperty("default")
            if type == "text" {
                let text = (defaultValue?.isString ?? false) ? (defaultValue?.toString() ?? "") : ""
                result.append(LumenPluginSetting(key: key, title: title, kind: .text(defaultValue: text)))
            } else {
                result.append(LumenPluginSetting(key: key, title: title, kind: .toggle(defaultValue: defaultValue?.toBool() ?? false)))
            }
        }
        return result
    }

    // MARK: Log and publishing

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        self.logLines.append("\(formatter.string(from: Date())) \(line)")
        if self.logLines.count > 200 {
            self.logLines.removeFirst(self.logLines.count - 200)
        }
    }

    private func publishSoon() {
        self.publish()
    }

    /// Snapshots the state on the plugin queue and hands it to the main queue.
    private func publish() {
        let enabled = Set(self.enabledIds())
        var infos: [LumenPluginInfo] = []
        for id in self.allIds() {
            let definition = self.loaded[id]?.definition
            func string(_ key: String) -> String? {
                guard let value = definition?.forProperty(key), value.isString else {
                    return nil
                }
                return value.toString()
            }
            infos.append(LumenPluginInfo(
                id: id,
                name: string("name") ?? id,
                author: string("author") ?? "",
                version: string("version") ?? "",
                description: string("description") ?? "",
                settings: self.parseSettings(id: id),
                isEnabled: enabled.contains(id),
                error: self.errors[id]
            ))
        }
        let logSnapshot = self.logLines
        DispatchQueue.main.async {
            self.plugins = infos
            self.log = logSnapshot
        }
    }

    // MARK: Samples

    private func installSamplesIfNeeded() {
        let flag = "lumen.plugins.samplesInstalled"
        if self.defaults.bool(forKey: flag) {
            return
        }
        self.defaults.set(true, forKey: flag)
        for (id, source) in LumenSamplePlugins.all {
            try? source.write(to: self.fileURL(id: id), atomically: true, encoding: .utf8)
        }
    }
}
