import Foundation
import SGSimpleSettings

// MARK: Lumen: raw TL hooks, as exteraGram's pre_request_hook / post_request_hook /
// on_update_hook. TelegramCore hands over requests, responses and updates by Android class
// name (only the ones some plugin subscribed to); the runtime runs the plugins' chain and
// answers keep / cancel / replace.

extension LumenPluginManager {
    /// How long an update may wait for the plugins before it is applied unchanged.
    private static let updateHookTimeout: DispatchTimeInterval = .milliseconds(300)

    func installTLHooks() {
        LumenHooks.preRequest = { [weak self] accountPeerId, name, json, completion in
            guard let self else {
                completion(.keep)
                return
            }
            self.queue.async {
                completion(self.runTLHook(kind: "pre", accountPeerId: accountPeerId, name: name, json: json, errorCode: 0, errorText: nil))
            }
        }
        LumenHooks.postRequest = { [weak self] accountPeerId, name, json, errorCode, errorText, completion in
            guard let self else {
                completion(.keep)
                return
            }
            self.queue.async {
                completion(self.runTLHook(kind: "post", accountPeerId: accountPeerId, name: name, json: json, errorCode: errorCode, errorText: errorText))
            }
        }
        LumenHooks.update = { [weak self] accountPeerId, name, json in
            guard let self else {
                return .keep
            }
            let box = LumenTLDecisionBox()
            let semaphore = DispatchSemaphore(value: 0)
            self.queue.async {
                box.set(self.runTLHook(kind: "update", accountPeerId: accountPeerId, name: name, json: json, errorCode: 0, errorText: nil))
                semaphore.signal()
            }
            if semaphore.wait(timeout: .now() + LumenPluginManager.updateHookTimeout) == .timedOut {
                self.queue.async {
                    self.appendLog("[\(name)] плагины не ответили за 0.3 с — апдейт применён без изменений")
                }
                return .keep
            }
            return box.get()
        }
    }

    /// Runs on the plugin queue.
    private func runTLHook(kind: String, accountPeerId: Int64, name: String, json: String?, errorCode: Int32, errorText: String?) -> LumenTLHookDecision {
        guard !self.loaded.isEmpty else {
            return .keep
        }
        self.activeAccountPeerId = accountPeerId
        var payload: [String: Any] = ["kind": kind, "name": name, "account": accountPeerId]
        if let json {
            payload["data"] = json
        }
        if let errorText {
            payload["errorCode"] = Int(errorCode)
            payload["errorText"] = errorText
        }
        guard let result = self.hostCall("tl_hook", payload) else {
            return .keep
        }
        self.runDeferred()
        switch result["decision"] as? String {
        case "cancel":
            return .cancel
        case "replace":
            guard let data = result["data"], !(data is NSNull) else {
                return .keep
            }
            return .replace(LumenJSON.string(from: data))
        case "error":
            let code = (result["code"] as? NSNumber)?.int32Value ?? 400
            return .error(code: code, text: result["text"] as? String ?? "PLUGIN_ERROR")
        default:
            if let error = result["error"] as? String {
                self.appendLog("[\(name)] \(error)")
            }
            return .keep
        }
    }

    /// send_request: a plugin's own TL call. The callback gets (result, error) where error is
    /// {"code", "text"} like TL_error.
    func sendTLRequest(_ arg: [String: Any]) {
        let callback = (arg["callback"] as? NSNumber)?.intValue
        let request = LumenJSON.string(from: arg["request"])
        guard let send = LumenHooks.sendTLRequest else {
            if let callback {
                self.fireCallback(callback, args: [NSNull(), ["code": 400, "text": "LUMEN_NOT_READY"]])
            }
            return
        }
        send(self.activeAccountPeerId, request) { [weak self] result, code, text in
            guard let self, let callback else {
                return
            }
            self.queue.async {
                var value: Any = NSNull()
                if let result, let object = LumenJSON.object(from: result) as? [String: Any], let inner = object["result"] {
                    value = inner
                }
                let error: Any = result == nil ? ["code": Int(code), "text": text ?? "ERROR"] : NSNull()
                self.fireCallback(callback, args: [value, error])
            }
        }
    }

    /// The runtime reports which names its plugins subscribed to after every change.
    func setTLHookInterest(_ arg: [String: Any]) {
        let exact = Set((arg["exact"] as? [Any] ?? []).compactMap { $0 as? String })
        let substrings = (arg["substrings"] as? [Any] ?? []).compactMap { $0 as? String }
        LumenHooks.tlHookFilter.set(exact: exact, substrings: substrings)
    }
}

private final class LumenTLDecisionBox {
    private let lock = NSLock()
    private var value: LumenTLHookDecision = .keep

    func set(_ value: LumenTLHookDecision) {
        self.lock.lock()
        self.value = value
        self.lock.unlock()
    }

    func get() -> LumenTLHookDecision {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }
}
