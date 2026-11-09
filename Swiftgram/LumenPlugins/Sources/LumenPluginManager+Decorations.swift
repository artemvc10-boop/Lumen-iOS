import Foundation
import SGSimpleSettings

// MARK: Lumen: profile/chat decorations (lumen.profile) and asynchronous network calls, so
// plugins that talk to their own servers never block the plugin queue (and the hooks on it).

extension LumenPluginManager {
    func installDecorationHooks() {
        LumenHooks.profileOpened = { [weak self] userId in
            self?.queue.async {
                self?.deliverDecorationEvent(["kind": "profile", "userId": userId])
            }
        }
        LumenHooks.chatUsersSeen = { [weak self] userIds in
            self?.queue.async {
                self?.deliverDecorationEvent(["kind": "chat", "userIds": userIds])
            }
        }
    }

    private func deliverDecorationEvent(_ payload: [String: Any]) {
        guard !self.loaded.isEmpty else {
            return
        }
        self.hostCall("decor_event", payload)
        self.runDeferred()
    }

    /// decorationSet {userId, spec} / decorationClear {userId} or {all: true} / decorationGet {userId}.
    func handleDecoration(op: String, arg: [String: Any]) -> Any? {
        let userId = (arg["userId"] as? NSNumber)?.int64Value ?? 0
        switch op {
        case "decorationSet":
            LumenDecorations.shared.set(userId: userId, spec: arg["spec"] as? [String: Any])
            return true
        case "decorationClear":
            if arg["all"] as? Bool == true {
                LumenDecorations.shared.clearAll()
            } else {
                LumenDecorations.shared.set(userId: userId, spec: nil)
            }
            return true
        default:
            return NSNull()
        }
    }

    /// httpAsync {method, url, headers, body(base64), timeout, callback}: the callback gets
    /// the same dict `http` returns.
    func handleHTTPAsync(_ arg: [String: Any]) {
        let callback = (arg["callback"] as? NSNumber)?.intValue
        guard let urlString = arg["url"] as? String, let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            if let callback {
                self.fireCallback(callback, args: [["error": "invalid url"]])
            }
            return
        }
        var request = URLRequest(url: url, timeoutInterval: (arg["timeout"] as? Double) ?? 30.0)
        request.httpMethod = (arg["method"] as? String) ?? "GET"
        if let headers = arg["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let body = arg["body"] as? String {
            request.httpBody = Data(base64Encoded: body)
        }
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            var result: [String: Any]
            if let error {
                result = ["error": error.localizedDescription]
            } else {
                var headers: [String: String] = [:]
                if let httpResponse = response as? HTTPURLResponse {
                    for (key, value) in httpResponse.allHeaderFields {
                        headers["\(key)"] = "\(value)"
                    }
                }
                result = ["status": (response as? HTTPURLResponse)?.statusCode ?? 0, "headers": headers, "body": (data ?? Data()).base64EncodedString(), "url": url.absoluteString]
            }
            guard let self, let callback else {
                return
            }
            self.queue.async {
                self.fireCallback(callback, args: [result])
            }
        }.resume()
    }

    /// download {url, path, headers, callback}: saves the body to `path` (inside the plugin's
    /// sandbox) without passing it through the runtime. The callback gets {ok, status, path}.
    func handleDownload(pluginId: String, _ arg: [String: Any]) {
        let callback = (arg["callback"] as? NSNumber)?.intValue
        let finish: ([String: Any]) -> Void = { [weak self] result in
            guard let self, let callback else {
                return
            }
            self.queue.async {
                self.fireCallback(callback, args: [result])
            }
        }
        guard let urlString = arg["url"] as? String, let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", let target = self.mapPath(arg["path"] as? String ?? "", pluginId: pluginId) else {
            finish(["ok": false, "error": "invalid url or path"])
            return
        }
        var request = URLRequest(url: url, timeoutInterval: (arg["timeout"] as? Double) ?? 60.0)
        if let headers = arg["headers"] as? [String: String] {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        URLSession.shared.downloadTask(with: request) { location, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, let location, (200 ..< 300).contains(status) else {
                finish(["ok": false, "status": status, "error": error?.localizedDescription ?? "HTTP \(status)"])
                return
            }
            let manager = FileManager.default
            try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.removeItem(at: target)
            do {
                try manager.moveItem(at: location, to: target)
                finish(["ok": true, "status": status, "path": target.path])
            } catch {
                finish(["ok": false, "status": status, "error": error.localizedDescription])
            }
        }.resume()
    }
}
