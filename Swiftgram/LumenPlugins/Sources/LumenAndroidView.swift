import Foundation
import UIKit

// MARK: Lumen: renders a plugin's Android view tree as native UIKit. Plugins build the tree
// with LinearLayout / TextView / EditText / ImageView etc. (see Runtime/py/_lumen_views.py);
// here it becomes a scrollable, interactive sheet. Layout is pragmatic, not pixel-exact:
// linear → stack, frame → overlay, scroll → UIScrollView, sizes from the layout params.

// MARK: Colors

enum LumenColor {
    /// Android colors are signed 32-bit ARGB ints.
    static func from(_ value: Any?) -> UIColor? {
        guard let number = value as? NSNumber else {
            if let dbl = value as? Double {
                return fromInt(Int64(dbl))
            }
            return nil
        }
        return fromInt(number.int64Value)
    }

    static func fromInt(_ raw: Int64) -> UIColor {
        let v = UInt32(truncatingIfNeeded: raw)
        let a = CGFloat((v >> 24) & 0xFF) / 255.0
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: a == 0 && v != 0 ? 1.0 : a)
    }

    static func toInt(_ color: UIColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let v = (UInt32(a * 255) << 24) | (UInt32(r * 255) << 16) | (UInt32(g * 255) << 8) | UInt32(b * 255)
        return Int(Int32(bitPattern: v))
    }
}

enum LumenAndroidTheme {
    /// Maps a Telegram theme key to an ARGB int in the app's current light/dark style.
    static func color(forKey key: String) -> Int {
        let dark = (LumenPresentation.keyWindow()?.traitCollection.userInterfaceStyle == .dark)
        return LumenColor.toInt(resolve(key: key, dark: dark))
    }

    private static func resolve(key: String, dark: Bool) -> UIColor {
        let accent = UIColor(red: 0.2, green: 0.52, blue: 0.96, alpha: 1.0)
        func grey(_ light: CGFloat, _ darkV: CGFloat) -> UIColor {
            let v = dark ? darkV : light
            return UIColor(white: v, alpha: 1.0)
        }
        switch key {
        case "key_dialogBackground", "key_windowBackgroundWhite", "key_actionBarDefault":
            return dark ? UIColor(white: 0.11, alpha: 1.0) : .white
        case "key_windowBackgroundGray", "key_dialogSearchBackground", "key_chat_messagePanelBackground":
            return dark ? UIColor(white: 0.17, alpha: 1.0) : UIColor(white: 0.94, alpha: 1.0)
        case "key_dialogTextBlack", "key_windowBackgroundWhiteBlackText", "key_chats_name", "key_actionBarDefaultTitle", "key_chat_messageTextIn":
            return dark ? .white : .black
        case "key_chats_actionIcon", "key_dialogButtonSelector", "key_chat_messageTextOut":
            return .white
        case "key_dialogTextLink", "key_windowBackgroundWhiteLinkText", "key_chats_actionBackground", "key_dialogButton", "key_featuredStickers_addButton":
            return accent
        case "key_dialogTextHint", "key_windowBackgroundWhiteHintText", "key_chats_message":
            return grey(0.6, 0.55)
        default:
            break
        }
        // Heuristics for the long tail of keys.
        if key.contains("Hint") {
            return grey(0.6, 0.55)
        }
        if key.contains("Gray") || key.contains("gray") || key.contains("Secondary") {
            return dark ? UIColor(white: 0.62, alpha: 1.0) : UIColor(white: 0.45, alpha: 1.0)
        }
        if key.contains("Link") || key.contains("action") || key.contains("Button") || key.contains("accent") || key.contains("Accent") {
            return accent
        }
        if key.contains("Background") || key.contains("background") {
            return dark ? UIColor(white: 0.14, alpha: 1.0) : UIColor(white: 0.97, alpha: 1.0)
        }
        return dark ? .white : .black
    }
}

// MARK: Presentation

extension LumenPluginManager {
    func presentAndroidView(_ arg: [String: Any]) {
        guard let id = arg["id"] as? Int else {
            return
        }
        let kind = arg["kind"] as? String ?? "dialog"
        let title = arg["title"] as? String
        let message = arg["message"] as? String
        let spec = arg["view"] as? [String: Any]
        let buttons = (arg["buttons"] as? [[String: Any]]) ?? []
        let dismiss = arg["dismiss"] as? Int
        self.activeViewPluginId = arg["plugin"] as? String ?? self.activeViewPluginId
        DispatchQueue.main.async {
            let controller = LumenAndroidContainerController(id: id, kind: kind, title: title, message: message, spec: spec, buttons: buttons, dismissCallback: dismiss, manager: self)
            self.presentedAndroidViews[id] = controller
            LumenPresentation.present(controller)
        }
    }

    func dismissAndroidView(_ idValue: Any?) {
        guard let id = idValue as? Int else {
            return
        }
        DispatchQueue.main.async {
            self.presentedAndroidViews[id]?.dismiss(animated: true)
            self.presentedAndroidViews[id] = nil
        }
    }

    func pushViewText(vid: Int, value: String) {
        self.queue.async {
            self.hostCall("set_view_text", ["vid": vid, "value": value])
        }
    }

    func fireViewCallback(_ id: Int) {
        self.fireCallbackFromMain(id)
    }

    func resolveImagePath(_ raw: String, pluginId: String) -> URL? {
        return self.mapPath(raw, pluginId: pluginId)
    }
}

// MARK: Container controller

final class LumenAndroidContainerController: UIViewController {
    private let id: Int
    private let kind: String
    private let titleText: String?
    private let messageText: String?
    private let spec: [String: Any]?
    private let buttons: [[String: Any]]
    private let dismissCallback: Int?
    private weak var manager: LumenPluginManager?
    private var didDismiss = false

    init(id: Int, kind: String, title: String?, message: String?, spec: [String: Any]?, buttons: [[String: Any]], dismissCallback: Int?, manager: LumenPluginManager) {
        self.id = id
        self.kind = kind
        self.titleText = title
        self.messageText = message
        self.spec = spec
        self.buttons = buttons
        self.dismissCallback = dismissCallback
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
        if kind == "bottom" {
            self.modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *), let sheet = self.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        } else {
            self.modalPresentationStyle = .formSheet
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let dark = self.traitCollection.userInterfaceStyle == .dark
        self.view.backgroundColor = dark ? UIColor(white: 0.11, alpha: 1.0) : .white

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 12.0
        root.translatesAutoresizingMaskIntoConstraints = false
        root.isLayoutMarginsRelativeArrangement = true
        root.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        if let titleText, !titleText.isEmpty {
            let label = UILabel()
            label.text = titleText
            label.font = .boldSystemFont(ofSize: 18.0)
            label.numberOfLines = 0
            root.addArrangedSubview(label)
        }
        if let messageText, !messageText.isEmpty {
            let label = UILabel()
            label.text = messageText
            label.font = .systemFont(ofSize: 15.0)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            root.addArrangedSubview(label)
        }

        var builder = LumenAndroidViewBuilder(manager: self.manager, pluginId: self.manager?.activeViewPluginId ?? "")
        if let spec, let rendered = builder.build(node: spec) {
            root.addArrangedSubview(rendered)
        }

        for button in self.buttons {
            let title = button["text"] as? String ?? "OK"
            let callback = button["callback"] as? Int
            let control = UIButton(type: .system)
            control.setTitle(title, for: .normal)
            control.titleLabel?.font = .systemFont(ofSize: 17.0, weight: .medium)
            control.addAction(UIAction { [weak self] _ in
                if let callback {
                    self?.manager?.fireViewCallback(callback)
                }
                self?.dismiss(animated: true)
            }, for: .touchUpInside)
            root.addArrangedSubview(control)
        }

        // Everything scrolls, so tall plugin UIs are reachable.
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        self.view.addSubview(scroll)
        scroll.addSubview(root)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            root.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            root.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.presentingViewController == nil {
            self.notifyDismiss()
        }
    }

    private func notifyDismiss() {
        if self.didDismiss {
            return
        }
        self.didDismiss = true
        self.manager?.presentedAndroidViews[self.id] = nil
        if let dismissCallback {
            self.manager?.fireViewCallback(dismissCallback)
        }
    }
}
