import Foundation
import UIKit
import Combine
import CryptoKit
import JavaScriptCore
import SGSimpleSettings

// MARK: Lumen plugins
//
// Plugins are exteraGram-style .plugin files: Python run by Skulpt inside one JSContext
// (LumenPyRuntime.js, built by ci/plugins/build_runtime.py), always on one serial queue
// because JSContext is not thread-safe. Swift calls the runtime's LumenHost.call(name, json);
// Python reaches the app through LumenNative.call(op, json), answered synchronously in
// LumenPluginManager+Native.swift.
//
// Chats use the Android plugins' dialog-id convention (a user is its id, a group or channel
// is minus its id); TelegramCore converts them back.

public struct LumenPluginInfo: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let author: String
    public let version: String
    public let description: String
    public let isEnabled: Bool
    public let error: String?
    /// Runs as Lumen's own iOS code instead of its Python (e.g. the meme library).
    public let isNative: Bool
}

public struct LumenPluginMenuItem: Equatable {
    public enum Kind: String {
        case message = "MESSAGE_CONTEXT_MENU"
        case chat = "CHAT_ACTION_MENU"
        case drawer = "DRAWER_MENU"
        case profile = "PROFILE_ACTION_MENU"
    }

    public let pluginId: String
    public let itemId: String
    public let kind: Kind
    public let title: String
    public let subtitle: String?
}

/// What a menu action receives about where it was opened.
public struct LumenPluginMessageContext {
    public let accountPeerId: Int64
    public let dialogId: Int64
    public let messageId: Int32
    public let text: String
    public let hasMedia: Bool
    /// The message's photo/video/file, copied where plugins may read it.
    public let mediaPath: String?

    public init(accountPeerId: Int64, dialogId: Int64, messageId: Int32, text: String, hasMedia: Bool, mediaPath: String? = nil) {
        self.accountPeerId = accountPeerId
        self.dialogId = dialogId
        self.messageId = messageId
        self.text = text
        self.hasMedia = hasMedia
        self.mediaPath = mediaPath
    }
}

/// One row of a plugin's settings page (its `create_settings()`), rendered natively.
public struct LumenPluginSettingItem: Identifiable {
    public let handle: Int
    public let type: String
    public let key: String?
    public let text: String
    public let subtext: String?
    public let defaultBool: Bool?
    public let defaultString: String?
    public let defaultInt: Int?
    public let items: [String]
    public let red: Bool
    public let clickable: Bool
    public let hasSubpage: Bool
    public let multiline: Bool

    public var id: Int { return self.handle }
}

public final class LumenPluginManager: ObservableObject {
    public static let shared = LumenPluginManager()

    /// Plugin ids Lumen implements natively (via LumenNativeRegistry); their Python is not run.
    public static var nativePluginIds: Set<String> {
        return Set(LumenNativeRegistry.factories.keys)
    }

    @Published public private(set) var plugins: [LumenPluginInfo] = []
    @Published public private(set) var logLines: [String] = []
    @Published public private(set) var menuItems: [LumenPluginMenuItem] = []

    let queue = DispatchQueue(label: "lumen.plugins")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var context: JSContext?
    private var host: JSValue?
    private var runtimeError: String?

    var loaded = Set<String>()
    var errors: [String: String] = [:]
    private var log: [String] = []

    /// callbackId -> whether the runtime still holds it (alerts, deferred work).
    let defaults = UserDefaults.standard
    private static let enabledKey = "lumen.plugins.enabledV2"

    /// Account the current hook/menu call belongs to; Lumen.send uses it.
    var activeAccountPeerId: Int64 = 0
    /// Native plugins (the meme library) register here to receive menu clicks.
    var nativeHandlers: [String: LumenNativePlugin] = [:]

    /// Callback ids the runtime queued with delay 0, fired after the current call returns.
    var pendingCallbacks: [Int] = []
    var nextAlertId = 1
    var presentedAlerts: [Int: UIAlertController] = [:]
    var alertDismissCallbacks: [Int: Int] = [:]

    /// Android view trees presented by plugins (AlertDialog.setView, BottomSheet).
    var presentedAndroidViews: [Int: UIViewController] = [:]
    /// Plugin whose view tree is being built/presented, for resolving its image paths.
    var activeViewPluginId: String = ""
    /// Keeps the photo/file picker delegate alive while the picker is on screen.
    var activePickerDelegate: AnyObject?

    public let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LumenPlugins", isDirectory: true)
    }()

    /// Per-plugin data folder (the plugin's own files live beside its source).
    public func dataDirectory(id: String) -> URL {
        return self.directory.appendingPathComponent(id, isDirectory: true)
    }

    private init() {
        self.queue.setSpecific(key: self.queueKey, value: true)
    }

    // MARK: Queue

    /// Runs on the plugin queue, inline when already on it, so a plugin calling back into
    /// the app from inside a hook cannot deadlock.
    func sync<T>(_ f: () -> T) -> T {
        if DispatchQueue.getSpecific(key: self.queueKey) == true {
            return f()
        }
        return self.queue.sync(execute: f)
    }

    // MARK: Startup

    public func start() {
        DispatchQueue.main.async {
            LumenScreenInfo.refresh()
        }
        self.queue.async {
            if self.context != nil {
                return
            }
            // Plugins Lumen implements natively; registered before any plugin loads.
            LumenNativeRegistry.factories[LumenMemeStore.pluginId] = { [weak self] in
                return LumenMemeLibraryPlugin(manager: self ?? LumenPluginManager.shared)
            }
            try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            self.installSamplesIfNeeded()
            self.setupRuntime()
            self.installHooks()
            for id in self.enabledIds() {
                self.loadPlugin(id: id)
            }
            self.registerNativePlugins()
            self.publish()
        }
    }

    private func setupRuntime() {
        guard let source = LumenPluginManager.runtimeSource() else {
            self.runtimeError = "Не найден LumenPyRuntime.js"
            self.appendLog(self.runtimeError!)
            return
        }
        guard let context = JSContext() else {
            self.runtimeError = "Не удалось создать JSContext"
            return
        }
        context.name = "Lumen plugins"
        context.exceptionHandler = { [weak self] _, exception in
            self?.appendLog("движок: \(exception?.toString() ?? "ошибка")")
        }
        self.installNative(in: context)
        context.evaluateScript(source, withSourceURL: URL(string: "LumenPyRuntime.js")!)
        guard let host = context.objectForKeyedSubscript("LumenHost"), !host.isUndefined else {
            self.runtimeError = "LumenPyRuntime.js не задал LumenHost"
            self.appendLog(self.runtimeError!)
            return
        }
        self.context = context
        self.host = host
    }

    private static func runtimeSource() -> String? {
        for bundle in [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks {
            if let url = bundle.url(forResource: "LumenPyRuntime", withExtension: "js"), let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    /// Calls LumenHost.call(name, json) and returns the parsed JSON result. Plugin queue only.
    @discardableResult
    func hostCall(_ name: String, _ payload: [String: Any]) -> [String: Any]? {
        guard let host = self.host else {
            return nil
        }
        let json = LumenJSON.string(from: payload)
        guard let result = host.invokeMethod("call", withArguments: [name, json]), let text = result.toString() else {
            return nil
        }
        return LumenJSON.object(from: text) as? [String: Any]
    }

    // MARK: Enabled set

    func enabledIds() -> [String] {
        return self.defaults.stringArray(forKey: LumenPluginManager.enabledKey) ?? []
    }

    private func setEnabledIds(_ ids: [String]) {
        self.defaults.set(Array(Set(ids)).sorted(), forKey: LumenPluginManager.enabledKey)
    }

    // MARK: Files

    func sourceURL(id: String) -> URL {
        return self.directory.appendingPathComponent(id + ".plugin")
    }

    func allIds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plugin" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    func readSource(id: String) -> String? {
        return try? String(contentsOf: self.sourceURL(id: id), encoding: .utf8)
    }

    // MARK: Logging

    func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        self.log.append("\(formatter.string(from: Date())) \(line)")
        if self.log.count > 300 {
            self.log.removeFirst(self.log.count - 300)
        }
    }

    public func clearLog() {
        self.queue.async {
            self.log.removeAll()
            self.publish()
        }
    }

    // MARK: Publish

    func publish() {
        let enabled = Set(self.enabledIds())
        var infos: [LumenPluginInfo] = []
        for id in self.allIds() {
            let meta = self.readSource(id: id).map { LumenPluginMetadata.parse(source: $0, fallbackId: id) }
            let isNative = LumenPluginManager.nativePluginIds.contains(id)
            infos.append(LumenPluginInfo(
                id: id,
                name: meta?.name ?? id,
                author: meta?.author ?? "",
                version: meta?.version ?? "",
                description: meta?.description ?? "",
                isEnabled: enabled.contains(id),
                error: self.errors[id],
                isNative: isNative
            ))
        }
        let logSnapshot = self.log
        let menuSnapshot = self.collectMenuItems()
        DispatchQueue.main.async {
            self.plugins = infos
            self.logLines = logSnapshot
            self.menuItems = menuSnapshot
        }
    }
}

public protocol LumenNativePlugin: AnyObject {
    var pluginId: String { get }
    func menuItems() -> [LumenPluginMenuItem]
    func performMenuItem(itemId: String, context: LumenPluginMessageContext)
    func settingsItems() -> [LumenPluginSettingItem]
    func handleSettingEvent(handle: Int, value: Any?)
}

public extension LumenNativePlugin {
    func handleSettingEvent(handle: Int, value: Any?) {
    }
}
