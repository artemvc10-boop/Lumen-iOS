import Foundation
import SGSimpleSettings

// MARK: Lumen: loading, installing and the menu/settings read back from the runtime.

extension LumenPluginManager {
    // MARK: Hooks into TelegramCore

    func installHooks() {
        LumenHooks.transformOutgoingText = { [weak self] accountPeerId, dialogId, text in
            guard let self else {
                return text
            }
            return self.sync {
                self.runSendHook(accountPeerId: accountPeerId, dialogId: dialogId, text: text)
            }
        }
        LumenHooks.incomingMessages = { [weak self] messages in
            self?.queue.async {
                self?.deliverIncoming(messages)
            }
        }
    }

    // MARK: Load / unload

    func loadPlugin(id: String) {
        if self.loaded.contains(id) {
            return
        }
        if LumenPluginManager.nativePluginIds.contains(id) {
            if self.nativeHandlers[id] == nil, let handler = LumenNativeRegistry.make(id: id) {
                self.nativeHandlers[id] = handler
            }
            self.errors[id] = nil
            self.loaded.insert(id)
            return
        }
        guard let raw = self.readSource(id: id) else {
            self.errors[id] = "Файл не найден"
            return
        }
        // Skulpt's tokenizer wants LF; downloaded plugins may carry CRLF.
        let source = raw.replacingOccurrences(of: "\r\n", with: "\n")
        try? FileManager.default.createDirectory(at: self.dataDirectory(id: id), withIntermediateDirectories: true)
        self.errors[id] = nil
        let result = self.hostCall("load_plugin", [
            "id": id,
            "path": self.sourceURL(id: id).path,
            "source": source,
            "name": LumenPluginMetadata.parse(source: source, fallbackId: id).name,
        ])
        if let error = result?["error"] as? String {
            self.errors[id] = error
            self.appendLog("[\(id)] \(error)")
        } else {
            self.loaded.insert(id)
        }
    }

    func unloadPlugin(id: String) {
        if !self.loaded.contains(id) {
            return
        }
        if LumenPluginManager.nativePluginIds.contains(id) {
            self.nativeHandlers[id] = nil
        } else {
            self.hostCall("unload_plugin", ["id": id])
        }
        self.loaded.remove(id)
    }

    // MARK: Install / remove / enable

    /// Copies a .plugin file in. It starts disabled; `enable` set true also turns it on.
    public func install(source rawSource: String, suggestedName: String, enable: Bool, completion: ((LumenPluginMetadata) -> Void)? = nil) {
        let source = rawSource.replacingOccurrences(of: "\r\n", with: "\n")
        self.queue.async {
            let meta = LumenPluginMetadata.parse(source: source, fallbackId: LumenPluginManager.sanitized(suggestedName))
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                if self.loaded.contains(meta.id) {
                    self.unloadPlugin(id: meta.id)
                }
                try source.write(to: self.sourceURL(id: meta.id), atomically: true, encoding: .utf8)
                self.appendLog("установлен плагин \(meta.name)")
                if enable {
                    self.setEnabled(meta.id, true, persistOnly: true)
                    self.loadPlugin(id: meta.id)
                }
            } catch {
                self.appendLog("не удалось установить \(meta.name): \(error.localizedDescription)")
            }
            self.publish()
            DispatchQueue.main.async {
                completion?(meta)
            }
        }
    }

    public func installFromFile(url: URL, enable: Bool, completion: ((LumenPluginMetadata?) -> Void)? = nil) {
        let accessing = url.startAccessingSecurityScopedResource()
        let source = try? String(contentsOf: url, encoding: .utf8)
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
        guard let source else {
            DispatchQueue.main.async {
                completion?(nil)
            }
            return
        }
        self.install(source: source, suggestedName: url.deletingPathExtension().lastPathComponent, enable: enable) { meta in
            completion?(meta)
        }
    }

    public func remove(id: String) {
        self.queue.async {
            self.unloadPlugin(id: id)
            try? FileManager.default.removeItem(at: self.sourceURL(id: id))
            try? FileManager.default.removeItem(at: self.dataDirectory(id: id))
            self.setEnabled(id, false, persistOnly: true)
            self.defaults.removeObject(forKey: self.settingsKey(id: id))
            self.errors[id] = nil
            self.publish()
        }
    }

    public func setEnabled(id: String, enabled: Bool) {
        self.queue.async {
            self.setEnabled(id, enabled, persistOnly: false)
            self.publish()
        }
    }

    private func setEnabled(_ id: String, _ enabled: Bool, persistOnly: Bool) {
        var ids = self.enabledIds().filter { $0 != id }
        if enabled {
            ids.append(id)
        }
        self.defaults.set(Array(Set(ids)).sorted(), forKey: "lumen.plugins.enabledV2")
        if persistOnly {
            return
        }
        if enabled {
            self.loadPlugin(id: id)
        } else {
            self.unloadPlugin(id: id)
        }
    }

    static func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let base = (name as NSString).deletingPathExtension
        let cleaned = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "plugin" : cleaned
    }

    // MARK: Menu items

    func collectMenuItems() -> [LumenPluginMenuItem] {
        var result: [LumenPluginMenuItem] = []
        for id in self.loaded.sorted() {
            if let native = self.nativeHandlers[id] {
                result.append(contentsOf: native.menuItems())
                continue
            }
            guard let items = self.hostCall("menu_items", ["plugin": id])?["items"] as? [[String: Any]] else {
                continue
            }
            for item in items {
                guard let itemId = item["itemId"] as? String, let title = item["text"] as? String, let typeString = item["type"] as? String, let kind = LumenPluginMenuItem.Kind(rawValue: typeString) else {
                    continue
                }
                result.append(LumenPluginMenuItem(pluginId: id, itemId: itemId, kind: kind, title: title, subtitle: item["subtext"] as? String))
            }
        }
        return result
    }

    public func performMenuItem(_ item: LumenPluginMenuItem, context: LumenPluginMessageContext) {
        LumenScreenInfo.refresh()
        self.queue.async {
            self.activeAccountPeerId = context.accountPeerId
            if let native = self.nativeHandlers[item.pluginId] {
                DispatchQueue.main.async {
                    native.performMenuItem(itemId: item.itemId, context: context)
                }
                return
            }
            var payload: [String: Any] = [
                "plugin": item.pluginId,
                "itemId": item.itemId,
                "dialogId": context.dialogId,
                "message": [
                    "id": Int(context.messageId),
                    "text": context.text,
                    "dialogId": context.dialogId,
                    "out": context.isOutgoingPlaceholder,
                    "hasMedia": context.hasMedia,
                    "date": 0,
                ],
            ]
            if let mediaPath = context.mediaPath {
                payload["mediaPath"] = mediaPath
            }
            self.hostCall("menu_click", payload)
            self.runDeferred()
        }
    }

    // MARK: Settings page

    public func settingsItems(id: String) -> [LumenPluginSettingItem] {
        return self.sync {
            if let native = self.nativeHandlers[id] {
                return native.settingsItems()
            }
            guard let items = self.hostCall("create_settings", ["plugin": id])?["items"] as? [[String: Any]] else {
                return []
            }
            return items.compactMap { LumenPluginManager.settingItem(from: $0) }
        }
    }

    public func settingsSubpage(id: String, handle: Int) -> [LumenPluginSettingItem] {
        return self.sync {
            guard let items = self.hostCall("settings_sub", ["plugin": id, "handle": handle])?["items"] as? [[String: Any]] else {
                return []
            }
            return items.compactMap { LumenPluginManager.settingItem(from: $0) }
        }
    }

    public func fireSettingEvent(id: String, handle: Int, value: Any?) {
        self.queue.async {
            if let native = self.nativeHandlers[id] {
                native.handleSettingEvent(handle: handle, value: value)
                return
            }
            self.hostCall("settings_event", ["plugin": id, "handle": handle, "value": value ?? NSNull()])
            self.runDeferred()
        }
    }

    static func settingItem(from raw: [String: Any]) -> LumenPluginSettingItem? {
        guard let handle = raw["handle"] as? Int, let type = raw["type"] as? String else {
            return nil
        }
        return LumenPluginSettingItem(
            handle: handle,
            type: type,
            key: raw["key"] as? String,
            text: raw["text"] as? String ?? "",
            subtext: raw["subtext"] as? String,
            defaultBool: raw["default"] as? Bool,
            defaultString: raw["default"] as? String,
            defaultInt: raw["default"] as? Int,
            items: (raw["items"] as? [String]) ?? [],
            red: raw["red"] as? Bool ?? false,
            clickable: raw["clickable"] as? Bool ?? false,
            hasSubpage: raw["hasSubpage"] as? Bool ?? false,
            multiline: raw["multiline"] as? Bool ?? false
        )
    }

    func settingsKey(id: String) -> String {
        return "lumen.plugins.\(id).settings"
    }

    // MARK: Hooks delivery

    private func runSendHook(accountPeerId: Int64, dialogId: Int64, text: String) -> String? {
        self.activeAccountPeerId = accountPeerId
        guard !self.loaded.isEmpty else {
            return text
        }
        guard let result = self.hostCall("send_hook", ["dialogId": dialogId, "text": text]) else {
            return text
        }
        self.runDeferred()
        if result["cancel"] as? Bool == true {
            return nil
        }
        return result["text"] as? String ?? text
    }

    private func deliverIncoming(_ messages: [LumenIncomingMessage]) {
        guard !self.loaded.isEmpty else {
            return
        }
        for message in messages {
            self.activeAccountPeerId = message.accountPeerId
            self.hostCall("update_hook", [
                "id": Int(message.messageId),
                "dialogId": message.dialogId,
                "authorId": message.authorId ?? message.dialogId,
                "text": message.text,
                "out": message.isOutgoing,
                "date": Int(message.date),
                "chatType": message.chatType,
                "isChannel": message.isChannel,
            ])
            self.runDeferred()
        }
    }

    // MARK: Samples

    func installSamplesIfNeeded() {
        let flag = "lumen.plugins.samplesInstalledV2"
        if self.defaults.bool(forKey: flag) {
            return
        }
        self.defaults.set(true, forKey: flag)
        for bundle in [Bundle.main] + Bundle.allBundles {
            let samples = bundle.urls(forResourcesWithExtension: "plugin", subdirectory: nil) ?? []
            for url in samples where url.lastPathComponent.hasPrefix("LumenSample_") {
                if let source = try? String(contentsOf: url, encoding: .utf8) {
                    let bare = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "LumenSample_", with: "")
                    let id = LumenPluginMetadata.parse(source: source, fallbackId: LumenPluginManager.sanitized(bare)).id
                    try? source.write(to: self.sourceURL(id: id), atomically: true, encoding: .utf8)
                }
            }
        }
    }
}

extension LumenPluginMessageContext {
    var isOutgoingPlaceholder: Bool {
        return false
    }
}
