import Foundation
import UIKit

// MARK: Lumen: deferred callbacks, bulletins and alerts for the plugin runtime.

extension LumenPluginManager {
    // MARK: Deferred callbacks

    /// Python's run_on_ui_thread / Thread.start / Timer register a callback id here.
    func scheduleDeferred(_ arg: [String: Any]) {
        guard let id = arg["id"] as? Int else {
            return
        }
        let delay = (arg["delay"] as? Double) ?? 0
        if delay <= 0 {
            self.pendingCallbacks.append(id)
        } else {
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.fireCallback(id)
            }
        }
    }

    /// Runs callbacks queued with delay 0 during the call that just finished.
    func runDeferred() {
        var guardCount = 0
        while !self.pendingCallbacks.isEmpty && guardCount < 200 {
            let id = self.pendingCallbacks.removeFirst()
            self.fireCallback(id)
            guardCount += 1
        }
    }

    func fireCallback(_ id: Int, args: [Any] = []) {
        self.hostCall("run_callback", ["id": id, "args": args])
        self.runDeferred()
    }

    func fireCallbackFromMain(_ id: Int, args: [Any] = []) {
        self.queue.async { [weak self] in
            self?.fireCallback(id, args: args)
        }
    }

    // MARK: Bulletins

    func showBulletin(_ arg: [String: Any]) {
        let kind: LumenToast.Kind
        switch arg["kind"] as? String {
        case "success": kind = .success
        case "error": kind = .error
        default: kind = .info
        }
        let text = arg["text"] as? String ?? ""
        let subtitle = arg["subtitle"] as? String
        let button = arg["button"] as? String
        let callback = arg["callback"] as? Int
        LumenToast.show(text, subtitle: subtitle, kind: kind, button: button, action: callback.map { id in
            { [weak self] in self?.fireCallbackFromMain(id) }
        })
    }

    // MARK: Alerts

    func showAlert(pluginId: String, _ arg: [String: Any]) -> Int {
        let alertId = self.nextAlertId
        self.nextAlertId += 1
        let title = arg["title"] as? String
        let message = arg["message"] as? String
        let buttons = (arg["buttons"] as? [[String: Any]]) ?? []
        let items = arg["items"] as? [String]
        let itemsCallback = arg["itemsCallback"] as? Int
        let dismissCallback = arg["dismissCallback"] as? Int

        DispatchQueue.main.async {
            let style: UIAlertController.Style = (items != nil && buttons.isEmpty) ? .actionSheet : .alert
            let controller = UIAlertController(title: title, message: message, preferredStyle: style)

            if let items, let itemsCallback {
                for (index, item) in items.enumerated() {
                    controller.addAction(UIAlertAction(title: item, style: .default) { [weak self] _ in
                        self?.fireCallbackFromMain(itemsCallback, args: [index])
                        self?.clearAlert(alertId)
                    })
                }
            }
            for button in buttons {
                let title = button["text"] as? String ?? "OK"
                let style: UIAlertAction.Style = (button["red"] as? Bool == true) ? .destructive : (button["which"] as? Int == -2 ? .cancel : .default)
                let callback = button["callback"] as? Int
                controller.addAction(UIAlertAction(title: title, style: style) { [weak self] _ in
                    if let callback {
                        self?.fireCallbackFromMain(callback)
                    }
                    self?.clearAlert(alertId)
                })
            }
            if controller.actions.isEmpty {
                controller.addAction(UIAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                    self?.clearAlert(alertId)
                })
            }
            if let dismissCallback {
                self.alertDismissCallbacks[alertId] = dismissCallback
            }
            self.presentedAlerts[alertId] = controller
            LumenPresentation.present(controller)
        }
        return alertId
    }

    func dismissAlert(_ idValue: Any?) {
        guard let id = idValue as? Int else {
            return
        }
        DispatchQueue.main.async {
            self.presentedAlerts[id]?.dismiss(animated: true)
            self.clearAlert(id)
        }
    }

    private func clearAlert(_ id: Int) {
        if let dismiss = self.alertDismissCallbacks[id] {
            self.fireCallbackFromMain(dismiss)
            self.alertDismissCallbacks[id] = nil
        }
        self.presentedAlerts[id] = nil
    }
}
