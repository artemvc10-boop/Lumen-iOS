import Foundation

// MARK: Lumen: file, archive and network operations for the plugin runtime. A plugin's
// paths are mapped into its own data folder or a shared Documents area; nothing escapes.

extension LumenPluginManager {
    /// Android-style paths are mapped under Documents; relative paths sit in the plugin's
    /// own data folder. The result is confined to the app container.
    func mapPath(_ raw: String, pluginId: String) -> URL? {
        var path = raw
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? self.directory
        var base: URL
        for prefix in ["/storage/emulated/0", "/sdcard", "/storage/self/primary"] {
            if path == prefix || path.hasPrefix(prefix + "/") {
                path = String(path.dropFirst(prefix.count))
                let url = documents.appendingPathComponent(path).standardizedFileURL
                return url.path.hasPrefix(documents.standardizedFileURL.path) ? url : nil
            }
        }
        if path.hasPrefix("/") {
            // An absolute path inside the app's own sandbox (Documents, Library, tmp) is fine;
            // anything else is not.
            let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.resolvingSymlinksInPath().path
            let temp = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.resolvingSymlinksInPath().path
            return (url.path.hasPrefix(home) || url.path.hasPrefix(temp)) ? url : nil
        }
        base = self.dataDirectory(id: pluginId)
        let url = base.appendingPathComponent(path).standardizedFileURL
        return url.path.hasPrefix(base.standardizedFileURL.path) ? url : nil
    }

    func handleFS(_ arg: [String: Any]) -> Any? {
        let pluginId = arg["plugin"] as? String ?? ""
        let action = arg["action"] as? String ?? ""
        let manager = FileManager.default
        func url(_ key: String) -> URL? {
            guard let raw = arg[key] as? String else {
                return nil
            }
            return self.mapPath(raw, pluginId: pluginId)
        }
        switch action {
        case "pluginsDir":
            try? manager.createDirectory(at: self.dataDirectory(id: pluginId), withIntermediateDirectories: true)
            return self.dataDirectory(id: pluginId).path
        case "cacheDir":
            return (manager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? self.directory).path
        case "filesDir":
            return self.dataDirectory(id: pluginId).path
        case "exists":
            return url("path").map { manager.fileExists(atPath: $0.path) } ?? false
        case "isDir":
            var isDir: ObjCBool = false
            if let u = url("path"), manager.fileExists(atPath: u.path, isDirectory: &isDir) {
                return isDir.boolValue
            }
            return false
        case "list":
            guard let u = url("path"), let names = try? manager.contentsOfDirectory(atPath: u.path) else {
                return NSNull()
            }
            return names
        case "mkdir":
            guard let u = url("path") else { return false }
            try? manager.createDirectory(at: u, withIntermediateDirectories: arg["parents"] as? Bool ?? false)
            return true
        case "remove":
            guard let u = url("path") else { return false }
            try? manager.removeItem(at: u)
            return true
        case "move":
            guard let src = url("src"), let dst = url("dst") else { return false }
            try? manager.removeItem(at: dst)
            try? manager.moveItem(at: src, to: dst)
            return true
        case "copy":
            guard let src = url("src"), let dst = url("dst") else { return false }
            try? manager.removeItem(at: dst)
            try? manager.copyItem(at: src, to: dst)
            return true
        case "stat":
            guard let u = url("path"), let attrs = try? manager.attributesOfItem(atPath: u.path) else {
                return NSNull()
            }
            var isDir: ObjCBool = false
            manager.fileExists(atPath: u.path, isDirectory: &isDir)
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return ["size": (attrs[.size] as? Int) ?? 0, "mtime": modified, "ctime": modified, "isDir": isDir.boolValue]
        case "readText":
            guard let u = url("path") else { return NSNull() }
            return (try? String(contentsOf: u, encoding: .utf8)) ?? NSNull()
        case "writeText":
            guard let u = url("path") else { return false }
            let text = arg["text"] as? String ?? ""
            if arg["append"] as? Bool == true, let handle = try? FileHandle(forWritingTo: u) {
                handle.seekToEndOfFile()
                handle.write(text.data(using: .utf8) ?? Data())
                handle.closeFile()
            } else {
                try? manager.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? text.data(using: .utf8)?.write(to: u)
            }
            return true
        case "readBase64":
            guard let u = url("path"), let data = try? Data(contentsOf: u) else { return NSNull() }
            return data.base64EncodedString()
        case "writeBase64":
            guard let u = url("path") else { return false }
            let data = Data(base64Encoded: arg["data"] as? String ?? "") ?? Data()
            try? manager.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: u)
            return true
        default:
            return NSNull()
        }
    }

    func handleZip(_ arg: [String: Any]) -> Any? {
        let pluginId = arg["plugin"] as? String ?? ""
        let action = arg["action"] as? String ?? ""
        guard let path = (arg["path"] as? String).flatMap({ self.mapPath($0, pluginId: pluginId) }) else {
            return NSNull()
        }
        switch action {
        case "create":
            let writer = LumenZipWriter()
            for entry in (arg["entries"] as? [[String: Any]]) ?? [] {
                guard let name = entry["name"] as? String else { continue }
                if let base64 = entry["data"] as? String {
                    writer.add(name: name, data: Data(base64Encoded: base64) ?? Data())
                } else if let source = (entry["path"] as? String).flatMap({ self.mapPath($0, pluginId: pluginId) }), let data = try? Data(contentsOf: source) {
                    writer.add(name: name, data: data)
                }
            }
            try? writer.finish().write(to: path)
            return true
        case "list":
            guard let data = try? Data(contentsOf: path), let reader = try? LumenZipReader(data: data) else {
                return NSNull()
            }
            return reader.entries.map { $0.name }
        case "read":
            guard let data = try? Data(contentsOf: path), let reader = try? LumenZipReader(data: data), let content = (try? reader.read(name: arg["name"] as? String ?? "")) ?? nil else {
                return NSNull()
            }
            return content.base64EncodedString()
        case "extract":
            guard let data = try? Data(contentsOf: path), let reader = try? LumenZipReader(data: data), let dst = (arg["dst"] as? String).flatMap({ self.mapPath($0, pluginId: pluginId) }) else {
                return false
            }
            let names = (arg["names"] as? [String]).map { Set($0) }
            try? reader.extract(to: dst, only: names)
            return true
        default:
            return NSNull()
        }
    }

    func handleHTTP(_ arg: [String: Any]) -> Any? {
        guard let urlString = arg["url"] as? String, let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return ["error": "invalid url"]
        }
        var request = URLRequest(url: url, timeoutInterval: (arg["timeout"] as? Double) ?? 20.0)
        request.httpMethod = (arg["method"] as? String) ?? "GET"
        if let headers = arg["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let body = arg["body"] as? String {
            request.httpBody = Data(base64Encoded: body)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any] = ["error": "timeout"]
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = ["error": error.localizedDescription]
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                var headers: [String: String] = [:]
                if let httpResponse = response as? HTTPURLResponse {
                    for (key, value) in httpResponse.allHeaderFields {
                        headers["\(key)"] = "\(value)"
                    }
                }
                result = ["status": status, "headers": headers, "body": (data ?? Data()).base64EncodedString(), "url": url.absoluteString]
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + ((arg["timeout"] as? Double) ?? 20.0) + 5.0)
        return result
    }

    // MARK: Settings values

    func settingValue(pluginId: String, key: String) -> Any? {
        if let stored = self.defaults.dictionary(forKey: self.settingsKey(id: pluginId))?[key] {
            return stored
        }
        return NSNull()
    }

    func setSettingValue(pluginId: String, key: String, value: Any?) {
        var stored = self.defaults.dictionary(forKey: self.settingsKey(id: pluginId)) ?? [:]
        if let value, !(value is NSNull) {
            stored[key] = value
        } else {
            stored[key] = nil
        }
        self.defaults.set(stored, forKey: self.settingsKey(id: pluginId))
    }
}
