import Foundation
import UIKit

// MARK: Lumen: the sheet/dialog that shows a plugin's Android view tree. It is rebuilt in
// place when the plugin changes its views (search filters, selection, toggles), keeping
// the text field being typed in.

final class LumenAndroidContainerController: UIViewController {
    private let id: Int
    private let kind: String
    private let titleText: String?
    private let messageText: String?
    private var spec: [String: Any]?
    private let buttons: [[String: Any]]
    private let dismissCallback: Int?
    private weak var manager: LumenPluginManager?
    private var didDismiss = false

    private let root = UIStackView()
    /// The plugin's view tree sits here, between the title/message and the buttons.
    private let contentHost = UIStackView()

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

        self.root.axis = .vertical
        self.root.spacing = 12.0
        self.root.translatesAutoresizingMaskIntoConstraints = false
        self.root.isLayoutMarginsRelativeArrangement = true
        self.root.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        if let titleText, !titleText.isEmpty {
            let label = UILabel()
            label.text = titleText
            label.font = .boldSystemFont(ofSize: 18.0)
            label.numberOfLines = 0
            self.root.addArrangedSubview(label)
        }
        if let messageText, !messageText.isEmpty {
            let label = UILabel()
            label.text = messageText
            label.font = .systemFont(ofSize: 15.0)
            label.textColor = .secondaryLabel
            label.numberOfLines = 0
            self.root.addArrangedSubview(label)
        }

        self.contentHost.axis = .vertical
        self.root.addArrangedSubview(self.contentHost)
        self.renderContent()

        for button in self.buttons {
            let title = button["text"] as? String ?? "OK"
            let callback = button["callback"] as? Int
            let control = UIButton(type: .system)
            control.setTitle(title, for: .normal)
            control.titleLabel?.font = .systemFont(ofSize: 17.0, weight: .medium)
            control.addAction(UIAction { [weak self] _ in
                guard let self else {
                    return
                }
                // Android dismisses an AlertDialog when one of its buttons is pressed.
                self.dismiss(animated: true)
                if let callback {
                    self.manager?.fireViewCallback(callback)
                }
            }, for: .touchUpInside)
            self.root.addArrangedSubview(control)
        }

        // Everything scrolls, so tall plugin UIs are reachable; the keyboard pushes it up.
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        self.view.addSubview(scroll)
        scroll.addSubview(self.root)
        let bottom: NSLayoutConstraint
        if #available(iOS 15.0, *) {
            bottom = scroll.bottomAnchor.constraint(equalTo: self.view.keyboardLayoutGuide.topAnchor)
        } else {
            bottom = scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            bottom,
            self.root.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            self.root.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            self.root.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            self.root.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ])
    }

    private func renderContent() {
        for view in self.contentHost.arrangedSubviews {
            self.contentHost.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let builder = LumenAndroidViewBuilder(manager: self.manager, pluginId: self.manager?.activeViewPluginId ?? "")
        if let spec = self.spec, let rendered = builder.build(node: spec) {
            self.contentHost.addArrangedSubview(rendered)
        }
    }

    /// The plugin changed its views: rebuild them, keeping the text field being typed in.
    func update(spec: [String: Any]?) {
        self.spec = spec
        guard self.isViewLoaded else {
            return
        }
        var focusedVid: Int?
        var cursorOffset: Int?
        if let field = LumenAndroidContainerController.findFirstResponder(in: self.contentHost) as? LumenPluginTextField {
            focusedVid = field.vid
            if let range = field.selectedTextRange {
                cursorOffset = field.offset(from: field.beginningOfDocument, to: range.start)
            }
        }
        UIView.performWithoutAnimation {
            self.renderContent()
            self.view.layoutIfNeeded()
        }
        guard let focusedVid, let field = LumenAndroidContainerController.findField(vid: focusedVid, in: self.contentHost) else {
            return
        }
        field.becomeFirstResponder()
        let target: UITextPosition
        if let cursorOffset, let position = field.position(from: field.beginningOfDocument, offset: cursorOffset) {
            target = position
        } else {
            target = field.endOfDocument
        }
        field.selectedTextRange = field.textRange(from: target, to: target)
    }

    private static func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder {
            return view
        }
        for subview in view.subviews {
            if let found = findFirstResponder(in: subview) {
                return found
            }
        }
        return nil
    }

    private static func findField(vid: Int, in view: UIView) -> LumenPluginTextField? {
        if let field = view as? LumenPluginTextField, field.vid == vid {
            return field
        }
        for subview in view.subviews {
            if let found = findField(vid: vid, in: subview) {
                return found
            }
        }
        return nil
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

extension LumenPluginManager {
    func updateAndroidView(_ arg: [String: Any]) {
        guard let id = arg["id"] as? Int else {
            return
        }
        let spec = arg["view"] as? [String: Any]
        DispatchQueue.main.async {
            (self.presentedAndroidViews[id] as? LumenAndroidContainerController)?.update(spec: spec)
        }
    }
}
