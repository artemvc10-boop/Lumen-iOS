import Foundation
import UIKit

// MARK: Lumen: turns one plugin view-tree node into a UIView. Used by the container that
// presents AlertDialog.setView / BottomSheet trees. Pragmatic layout, see LumenAndroidView.

struct LumenAndroidViewBuilder {
    weak var manager: LumenPluginManager?
    let pluginId: String

    func build(node: [String: Any]) -> UIView? {
        guard let type = node["type"] as? String else {
            return nil
        }
        if (node["visibility"] as? Int ?? 0) == 8 { // GONE
            return nil
        }
        let props = node["props"] as? [String: Any] ?? [:]
        let view: UIView
        switch type {
        case "linear":
            view = self.buildLinear(node: node, props: props)
        case "scroll", "hscroll":
            view = self.buildScroll(node: node, props: props, horizontal: type == "hscroll")
        case "frame":
            view = self.buildFrame(node: node, props: props)
        case "text", "button":
            view = self.buildLabel(node: node, props: props, isButton: type == "button")
        case "edit":
            view = self.buildEdit(node: node, props: props)
        case "image":
            view = self.buildImage(node: node, props: props)
        default:
            view = self.buildFrame(node: node, props: props)
        }
        self.applyCommon(view, node: node, props: props)
        return view
    }

    // MARK: Containers

    private func children(_ node: [String: Any]) -> [[String: Any]] {
        return node["children"] as? [[String: Any]] ?? []
    }

    private func buildLinear(node: [String: Any], props: [String: Any]) -> UIView {
        let stack = UIStackView()
        stack.axis = (props["orientation"] as? Int ?? 1) == 0 ? .horizontal : .vertical
        stack.alignment = .fill
        stack.distribution = .fill
        stack.spacing = 0
        for childNode in self.children(node) {
            if let child = self.build(node: childNode) {
                stack.addArrangedSubview(child)
                self.applySize(child, node: childNode, inStack: stack.axis)
            }
        }
        self.applyPadding(stack, props: props)
        return stack
    }

    private func buildScroll(node: [String: Any], props: [String: Any], horizontal: Bool) -> UIView {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = !horizontal
        scroll.showsHorizontalScrollIndicator = horizontal
        let content: UIView
        let childNodes = self.children(node)
        if childNodes.count == 1, let only = self.build(node: childNodes[0]) {
            content = only
        } else {
            let stack = UIStackView()
            stack.axis = horizontal ? .horizontal : .vertical
            for childNode in childNodes {
                if let child = self.build(node: childNode) {
                    stack.addArrangedSubview(child)
                }
            }
            content = stack
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        var constraints = [
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ]
        if horizontal {
            constraints.append(content.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor))
        } else {
            constraints.append(content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return scroll
    }

    private func buildFrame(node: [String: Any], props: [String: Any]) -> UIView {
        let container = UIView()
        for childNode in self.children(node) {
            guard let child = self.build(node: childNode) else {
                continue
            }
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
            self.pinInFrame(child, node: childNode, container: container)
        }
        self.applyPadding(container, props: props)
        return container
    }

    // MARK: Leaves

    private func buildLabel(node: [String: Any], props: [String: Any], isButton: Bool) -> UIView {
        let label = UILabel()
        label.text = node["text"] as? String
        label.numberOfLines = (props["singleLine"] as? Bool == true) ? 1 : (props["maxLines"] as? Int ?? 0)
        label.font = .systemFont(ofSize: CGFloat(props["textSize"] as? Double ?? 15.0))
        if let color = LumenColor.from(props["textColor"]) {
            label.textColor = color
        } else {
            label.textColor = .label
        }
        label.textAlignment = self.alignment(props["gravity"] as? Int)
        self.applyPadding(label, props: props)
        return label
    }

    private func buildEdit(node: [String: Any], props: [String: Any]) -> UIView {
        let multiline = (props["singleLine"] as? Bool) == false && (props["inputType"] as? Int ?? 1) & 131072 != 0
        let field = LumenPluginTextField(vid: node["vid"] as? Int ?? 0, manager: self.manager, multiline: multiline)
        field.text = node["text"] as? String
        field.placeholder = props["hint"] as? String
        if let color = LumenColor.from(props["textColor"]) {
            field.textColor = color
        }
        field.font = .systemFont(ofSize: CGFloat(props["textSize"] as? Double ?? 16.0))
        if let maxLength = props["maxLength"] as? Int {
            field.maxLength = maxLength
        }
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    private func buildImage(node: [String: Any], props: [String: Any]) -> UIView {
        let imageView = UIImageView()
        imageView.clipsToBounds = true
        switch props["scaleType"] as? String {
        case "centerCrop":
            imageView.contentMode = .scaleAspectFill
        case "center":
            imageView.contentMode = .center
        default:
            imageView.contentMode = .scaleAspectFit
        }
        if let path = props["image"] as? String, let url = self.manager?.resolveImagePath(path, pluginId: self.pluginId), let image = UIImage(contentsOfFile: url.path) {
            imageView.image = image
        } else {
            imageView.backgroundColor = UIColor.secondarySystemBackground
        }
        return imageView
    }

    // MARK: Common styling

    private func applyCommon(_ view: UIView, node: [String: Any], props: [String: Any]) {
        if (node["visibility"] as? Int ?? 0) == 4 { // INVISIBLE
            view.isHidden = true
        }
        if let alpha = props["alpha"] as? Double {
            view.alpha = CGFloat(alpha)
        }
        if let background = props["background"] as? [String: Any] {
            self.applyBackground(view, background)
        }
        if let callbackId = node["clickCallback"] as? Int {
            self.attachTap(view, callbackId: callbackId)
        }
        if let callbackId = node["longClickCallback"] as? Int {
            self.attachLongPress(view, callbackId: callbackId)
        }
    }

    private func applyBackground(_ view: UIView, _ spec: [String: Any]) {
        if let color = LumenColor.from(spec["color"]) {
            view.backgroundColor = color
        }
        if let radius = spec["radius"] as? Double, radius > 0 {
            view.layer.cornerRadius = CGFloat(radius)
            view.clipsToBounds = true
        }
        if let strokeWidth = spec["strokeWidth"] as? Int, strokeWidth > 0 {
            view.layer.borderWidth = CGFloat(strokeWidth)
            view.layer.borderColor = (LumenColor.from(spec["strokeColor"]) ?? UIColor.separator).cgColor
        }
    }

    private func applyPadding(_ view: UIView, props: [String: Any]) {
        guard let padding = props["padding"] as? [Int], padding.count == 4 else {
            return
        }
        let insets = UIEdgeInsets(top: CGFloat(padding[1]), left: CGFloat(padding[0]), bottom: CGFloat(padding[3]), right: CGFloat(padding[2]))
        if let stack = view as? UIStackView {
            stack.isLayoutMarginsRelativeArrangement = true
            stack.layoutMargins = insets
        } else if let label = view as? UILabel {
            label.lumenInsets = insets
        } else {
            view.layoutMargins = insets
        }
    }

    // MARK: Sizes

    private func layoutParams(_ node: [String: Any]) -> [String: Any]? {
        return (node["props"] as? [String: Any])?["layout"] as? [String: Any]
    }

    private func applySize(_ view: UIView, node: [String: Any], inStack axis: NSLayoutConstraint.Axis) {
        guard let params = self.layoutParams(node) else {
            return
        }
        let width = params["width"] as? Int ?? -2
        let height = params["height"] as? Int ?? -2
        if height >= 0 {
            view.heightAnchor.constraint(equalToConstant: CGFloat(height)).isActive = true
        }
        if width >= 0 {
            view.widthAnchor.constraint(equalToConstant: CGFloat(width)).isActive = true
        }
        // A horizontal stack child that should hug its content rather than stretch.
        if axis == .horizontal && width == -2 {
            view.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        if let margins = params["margins"] as? [Int], margins.count == 4 {
            view.layoutMargins = UIEdgeInsets(top: CGFloat(margins[1]), left: CGFloat(margins[0]), bottom: CGFloat(margins[3]), right: CGFloat(margins[2]))
        }
    }

    private func pinInFrame(_ view: UIView, node: [String: Any], container: UIView) {
        let params = self.layoutParams(node)
        let width = params?["width"] as? Int ?? -2
        let height = params?["height"] as? Int ?? -2
        let gravity = params?["gravity"] as? Int ?? -1
        let margins = params?["margins"] as? [Int] ?? [0, 0, 0, 0]
        var constraints: [NSLayoutConstraint] = []
        if height >= 0 {
            constraints.append(view.heightAnchor.constraint(equalToConstant: CGFloat(height)))
        }
        if width >= 0 {
            constraints.append(view.widthAnchor.constraint(equalToConstant: CGFloat(width)))
        }
        if width == -1 {
            constraints.append(view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: CGFloat(margins[0])))
            constraints.append(view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -CGFloat(margins[2])))
        } else if (gravity & 5) == 5 || (gravity & 8388613) == 8388613 { // RIGHT / END
            constraints.append(view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -CGFloat(margins[2])))
        } else if (gravity & 1) == 1 { // CENTER_HORIZONTAL
            constraints.append(view.centerXAnchor.constraint(equalTo: container.centerXAnchor))
        } else {
            constraints.append(view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: CGFloat(margins[0])))
        }
        if height == -1 {
            constraints.append(view.topAnchor.constraint(equalTo: container.topAnchor, constant: CGFloat(margins[1])))
            constraints.append(view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -CGFloat(margins[3])))
        } else if (gravity & 80) == 80 { // BOTTOM
            constraints.append(view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -CGFloat(margins[3])))
        } else if (gravity & 16) == 16 { // CENTER_VERTICAL
            constraints.append(view.centerYAnchor.constraint(equalTo: container.centerYAnchor))
        } else {
            constraints.append(view.topAnchor.constraint(equalTo: container.topAnchor, constant: CGFloat(margins[1])))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func alignment(_ gravity: Int?) -> NSTextAlignment {
        guard let gravity else {
            return .natural
        }
        if (gravity & 1) == 1 || gravity == 17 {
            return .center
        }
        if (gravity & 5) == 5 {
            return .right
        }
        return .natural
    }

    // MARK: Interaction

    private func attachTap(_ view: UIView, callbackId: Int) {
        view.isUserInteractionEnabled = true
        let handler = LumenTapHandler(callbackId: callbackId, manager: self.manager)
        let recognizer = UITapGestureRecognizer(target: handler, action: #selector(LumenTapHandler.fire))
        view.addGestureRecognizer(recognizer)
        objc_setAssociatedObject(view, &LumenTapHandler.key, handler, .OBJC_ASSOCIATION_RETAIN)
    }

    private func attachLongPress(_ view: UIView, callbackId: Int) {
        view.isUserInteractionEnabled = true
        let handler = LumenTapHandler(callbackId: callbackId, manager: self.manager)
        let recognizer = UILongPressGestureRecognizer(target: handler, action: #selector(LumenTapHandler.fireLong(_:)))
        view.addGestureRecognizer(recognizer)
        objc_setAssociatedObject(view, &LumenTapHandler.longKey, handler, .OBJC_ASSOCIATION_RETAIN)
    }
}

final class LumenTapHandler: NSObject {
    static var key: UInt8 = 0
    static var longKey: UInt8 = 0
    private let callbackId: Int
    private weak var manager: LumenPluginManager?

    init(callbackId: Int, manager: LumenPluginManager?) {
        self.callbackId = callbackId
        self.manager = manager
    }

    @objc func fire() {
        self.manager?.fireViewCallback(self.callbackId)
    }

    @objc func fireLong(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            self.manager?.fireViewCallback(self.callbackId)
        }
    }
}

/// A text field that pushes edits back to the plugin so getText() stays current.
final class LumenPluginTextField: UITextField, UITextFieldDelegate {
    let vid: Int
    weak var manager: LumenPluginManager?
    var maxLength: Int = 0

    init(vid: Int, manager: LumenPluginManager?, multiline: Bool) {
        self.vid = vid
        self.manager = manager
        super.init(frame: .zero)
        self.delegate = self
        self.borderStyle = .none
        self.addTarget(self, action: #selector(self.editingChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func editingChanged() {
        if self.maxLength > 0, let text = self.text, text.count > self.maxLength {
            self.text = String(text.prefix(self.maxLength))
        }
        self.manager?.pushViewText(vid: self.vid, value: self.text ?? "")
    }
}

// MARK: Padded label

private var lumenInsetsKey: UInt8 = 0

extension UILabel {
    var lumenInsets: UIEdgeInsets {
        get { return (objc_getAssociatedObject(self, &lumenInsetsKey) as? NSValue)?.uiEdgeInsetsValue ?? .zero }
        set { objc_setAssociatedObject(self, &lumenInsetsKey, NSValue(uiEdgeInsets: newValue), .OBJC_ASSOCIATION_RETAIN) }
    }
}
