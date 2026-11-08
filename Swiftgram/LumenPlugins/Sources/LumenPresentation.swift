import Foundation
import UIKit

// MARK: Lumen: presenting plugin alerts, toasts and sheets over whatever is on screen.

enum LumenPresentation {
    static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard var top = (windows.first(where: { $0.isKeyWindow }) ?? windows.first)?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    static func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow }) ?? windows.first
    }

    static func present(_ controller: UIViewController) {
        DispatchQueue.main.async {
            topViewController()?.present(controller, animated: true)
        }
    }

    static func share(fileURL: URL) {
        DispatchQueue.main.async {
            guard let top = topViewController() else {
                return
            }
            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1.0, height: 1.0)
            }
            top.present(controller, animated: true)
        }
    }
}

/// A short message at the bottom of the screen, like Telegram's bulletins.
public enum LumenToast {
    public enum Kind {
        case info
        case success
        case error
    }

    private static weak var current: UIView?

    public static func show(_ text: String, subtitle: String? = nil, kind: Kind = .info, button: String? = nil, action: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let window = LumenPresentation.keyWindow() else {
                return
            }
            current?.removeFromSuperview()

            let container = UIView()
            container.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
            container.layer.cornerRadius = 14.0
            container.translatesAutoresizingMaskIntoConstraints = false

            let icon = UILabel()
            switch kind {
            case .info:
                icon.text = "ℹ️"
            case .success:
                icon.text = "✅"
            case .error:
                icon.text = "⚠️"
            }
            icon.setContentHuggingPriority(.required, for: .horizontal)

            let label = UILabel()
            label.numberOfLines = 3
            label.textColor = .white
            label.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
            label.text = subtitle.map { "\(text)\n\($0)" } ?? text

            let stack = UIStackView(arrangedSubviews: [icon, label])
            stack.axis = .horizontal
            stack.spacing = 10.0
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false

            if let button {
                let control = UIButton(type: .system)
                control.setTitle(button, for: .normal)
                control.setTitleColor(UIColor(red: 0.45, green: 0.7, blue: 1.0, alpha: 1.0), for: .normal)
                control.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
                control.setContentHuggingPriority(.required, for: .horizontal)
                control.addAction(UIAction { [weak container] _ in
                    action?()
                    container?.removeFromSuperview()
                }, for: .touchUpInside)
                stack.addArrangedSubview(control)
            }

            container.addSubview(stack)
            window.addSubview(container)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14.0),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14.0),
                stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12.0),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12.0),
                container.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 12.0),
                container.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -12.0),
                container.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -60.0),
            ])
            current = container
            container.alpha = 0.0
            UIView.animate(withDuration: 0.2) {
                container.alpha = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (button == nil ? 2.5 : 4.5)) { [weak container] in
                UIView.animate(withDuration: 0.25, animations: {
                    container?.alpha = 0.0
                }, completion: { _ in
                    container?.removeFromSuperview()
                })
            }
        }
    }
}
