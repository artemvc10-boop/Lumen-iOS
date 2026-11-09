import Foundation
import UIKit

// MARK: Lumen

/// Per-user profile and chat decorations that plugins provide (lumen.profile in the plugin
/// runtime). Lumen renders them natively: the profile header (banner, avatar shape, name
/// style, "thought"), the profile page (background, block and text colors, sound) and chats
/// (author name color, avatar ring, tag).
///
/// Plugins learn what to load through `LumenHooks.profileOpened` / `chatUsersSeen`.
/// Decorations are kept on disk so a profile looks right the moment it opens.
public final class LumenDecorations {
    public static let shared = LumenDecorations()

    /// Posted on the main queue with `userInfo["userId"]` (Int64) when one changes.
    public static let didChangeNotification = Notification.Name("LumenDecorationsDidChange")

    private let lock = NSLock()
    private var items: [Int64: LumenDecoration] = [:]
    private var raw: [String: Any] = [:]
    private var seenAt: [Int64: Double] = [:]
    private var pendingSeen: Set<Int64> = []
    private var seenFlushScheduled = false
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = base.appendingPathComponent("LumenDecorations.json")
        if let data = try? Data(contentsOf: self.fileURL), let object = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
            self.raw = object
            for (key, value) in object {
                if let id = Int64(key), let spec = value as? [String: Any] {
                    self.items[id] = LumenDecoration(spec: spec)
                }
            }
        }
    }

    /// `userId` is the Android-style dialog id (a user's id; minus the id for chats).
    public func decoration(userId: Int64) -> LumenDecoration? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.items[userId]
    }

    public func set(userId: Int64, spec: [String: Any]?) {
        self.lock.lock()
        if let spec, !spec.isEmpty {
            self.items[userId] = LumenDecoration(spec: spec)
            self.raw[String(userId)] = spec
        } else {
            self.items[userId] = nil
            self.raw[String(userId)] = nil
        }
        let snapshot = self.raw
        self.lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            if JSONSerialization.isValidJSONObject(snapshot), let data = try? JSONSerialization.data(withJSONObject: snapshot, options: []) {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
        let post = {
            NotificationCenter.default.post(name: LumenDecorations.didChangeNotification, object: self, userInfo: ["userId": userId])
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    public func clearAll() {
        self.lock.lock()
        let ids = Array(self.items.keys)
        self.lock.unlock()
        for id in ids {
            self.set(userId: id, spec: nil)
        }
    }

    /// A profile opened: plugins may fetch its decoration.
    public func noteProfileOpened(userId: Int64) {
        DispatchQueue.main.async {
            LumenHooks.profileOpened?(userId)
        }
    }

    /// A user's message or avatar is on screen in a chat. Batched; each user is reported at
    /// most once every 10 minutes so plugins can refresh without flooding.
    public func noteSeenInChat(userId: Int64) {
        guard userId != 0 else {
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        self.lock.lock()
        if let last = self.seenAt[userId], now - last < 600.0 {
            self.lock.unlock()
            return
        }
        self.seenAt[userId] = now
        self.pendingSeen.insert(userId)
        let schedule = !self.seenFlushScheduled
        self.seenFlushScheduled = true
        self.lock.unlock()
        if schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.lock.lock()
                let ids = Array(self.pendingSeen)
                self.pendingSeen.removeAll()
                self.seenFlushScheduled = false
                self.lock.unlock()
                if !ids.isEmpty {
                    LumenHooks.chatUsersSeen?(ids)
                }
            }
        }
    }
}

// MARK: Spec

public struct LumenFill {
    public enum Kind {
        case color(UIColor)
        case linearGradient([UIColor], angle: CGFloat)
        case radialGradient([UIColor], center: CGPoint, radius: CGFloat)
        case image(String)
    }

    public let kind: Kind
    public let alpha: CGFloat
    /// Black overlay strength, 0...1.
    public let dim: CGFloat
    /// Fraction of the height at the bottom that fades out, 0...1.
    public let fade: CGFloat

    init?(_ spec: Any?) {
        guard let spec = spec as? [String: Any] else {
            return nil
        }
        let type = spec["type"] as? String ?? "color"
        let colors = (spec["colors"] as? [Any] ?? []).compactMap(lumenColor)
        switch type {
        case "image":
            guard let path = spec["image"] as? String, !path.isEmpty else {
                return nil
            }
            self.kind = .image(path)
        case "gradient", "linear":
            if colors.count >= 2 {
                self.kind = .linearGradient(colors, angle: lumenCGFloat(spec["angle"]) ?? 0.0)
            } else if let first = colors.first {
                self.kind = .color(first)
            } else {
                return nil
            }
        case "radial":
            guard colors.count >= 2 else {
                return nil
            }
            let center = (spec["center"] as? [Any]).flatMap { values -> CGPoint? in
                guard values.count == 2, let x = lumenCGFloat(values[0]), let y = lumenCGFloat(values[1]) else {
                    return nil
                }
                return CGPoint(x: x, y: y)
            } ?? CGPoint(x: 0.5, y: 0.5)
            self.kind = .radialGradient(colors, center: center, radius: lumenCGFloat(spec["radius"]) ?? 1.0)
        default:
            guard let color = lumenColor(spec["color"]) ?? colors.first else {
                return nil
            }
            self.kind = .color(color)
        }
        self.alpha = max(0.0, min(1.0, lumenCGFloat(spec["alpha"]) ?? 1.0))
        self.dim = max(0.0, min(1.0, lumenCGFloat(spec["dim"]) ?? 0.0))
        self.fade = max(0.0, min(1.0, lumenCGFloat(spec["fade"]) ?? 0.0))
    }
}

public struct LumenNameStyle {
    public let color: UIColor?
    public let gradient: [UIColor]
    public let gradientAngle: CGFloat
    public let glowColor: UIColor?
    public let glowRadius: CGFloat
    public let glowStrength: CGFloat
    public let shadowColor: UIColor?
    public let shadowRadius: CGFloat
    public let shadowOffset: CGSize
    /// Relative font size, 1 = default.
    public let scale: CGFloat
    /// A font file (ttf/otf) to draw the name with.
    public let fontPath: String?

    init?(_ spec: Any?) {
        guard let spec = spec as? [String: Any] else {
            return nil
        }
        self.color = lumenColor(spec["color"])
        self.gradient = (spec["gradient"] as? [Any] ?? []).compactMap(lumenColor)
        self.gradientAngle = lumenCGFloat(spec["angle"]) ?? 0.0
        let glow = spec["glow"] as? [String: Any]
        self.glowColor = lumenColor(glow?["color"])
        self.glowRadius = lumenCGFloat(glow?["radius"]) ?? 8.0
        self.glowStrength = max(0.0, min(1.0, lumenCGFloat(glow?["strength"]) ?? 1.0))
        let shadow = spec["shadow"] as? [String: Any]
        self.shadowColor = lumenColor(shadow?["color"])
        self.shadowRadius = lumenCGFloat(shadow?["radius"]) ?? 4.0
        self.shadowOffset = CGSize(width: lumenCGFloat(shadow?["dx"]) ?? 1.0, height: lumenCGFloat(shadow?["dy"]) ?? 1.0)
        self.scale = max(0.5, min(1.6, lumenCGFloat(spec["scale"]) ?? 1.0))
        self.fontPath = spec["font"] as? String
    }

    /// The single color to draw with: the solid one, or the gradient's first.
    public var primaryColor: UIColor? {
        return self.color ?? self.gradient.first
    }
}

public struct LumenAvatarStyle {
    /// 0 circle, 1 rounded (radius), 2 square, 3 hexagon, 4 pentagon, 5 star, 6 heart.
    public let shape: Int
    /// Corner radius in points for the rounded shape (of a 100 pt avatar).
    public let radius: CGFloat
    public let alpha: CGFloat

    init?(_ spec: Any?) {
        guard let spec = spec as? [String: Any] else {
            return nil
        }
        self.shape = (spec["shape"] as? NSNumber)?.intValue ?? 0
        self.radius = lumenCGFloat(spec["radius"]) ?? 18.0
        self.alpha = max(0.05, min(1.0, lumenCGFloat(spec["alpha"]) ?? 1.0))
    }

    /// The outline for an avatar of `size`.
    public func path(size: CGSize) -> UIBezierPath {
        let rect = CGRect(origin: .zero, size: size)
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        switch self.shape {
        case 1:
            return UIBezierPath(roundedRect: rect, cornerRadius: min(side / 2.0, self.radius * side / 100.0))
        case 2:
            return UIBezierPath(rect: rect)
        case 3, 4:
            let count = self.shape == 3 ? 6 : 5
            let path = UIBezierPath()
            for index in 0 ..< count {
                let angle = -CGFloat.pi / 2.0 + CGFloat(index) * 2.0 * CGFloat.pi / CGFloat(count)
                let point = CGPoint(x: center.x + cos(angle) * side / 2.0, y: center.y + sin(angle) * side / 2.0)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.close()
            return path
        case 5:
            let path = UIBezierPath()
            for index in 0 ..< 10 {
                let radius = index % 2 == 0 ? side / 2.0 : side / 2.0 * 0.42
                let angle = -CGFloat.pi / 2.0 + CGFloat(index) * CGFloat.pi / 5.0
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.close()
            return path
        case 6:
            // The classic parametric heart, scaled to fit.
            var points: [CGPoint] = []
            for index in 0 ... 72 {
                let t = CGFloat(index) * 2.0 * CGFloat.pi / 72.0
                let x = 16.0 * pow(sin(t), 3.0)
                let y = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
                points.append(CGPoint(x: x, y: -y))
            }
            let minX = points.map(\.x).min() ?? 0.0, maxX = points.map(\.x).max() ?? 1.0
            let minY = points.map(\.y).min() ?? 0.0, maxY = points.map(\.y).max() ?? 1.0
            let scale = side / max(maxX - minX, maxY - minY)
            let offsetX = center.x - (minX + maxX) / 2.0 * scale
            let offsetY = center.y - (minY + maxY) / 2.0 * scale
            let path = UIBezierPath()
            for (index, point) in points.enumerated() {
                let mapped = CGPoint(x: point.x * scale + offsetX, y: point.y * scale + offsetY)
                if index == 0 {
                    path.move(to: mapped)
                } else {
                    path.addLine(to: mapped)
                }
            }
            path.close()
            return path
        default:
            return UIBezierPath(ovalIn: rect)
        }
    }
}

public struct LumenChatStyle {
    public let nameColor: UIColor?
    public let ringColors: [UIColor]
    public let ringWidth: CGFloat
    public let tagText: String?
    public let tagColor: UIColor?
    public let badgeImagePath: String?

    init?(_ spec: Any?) {
        guard let spec = spec as? [String: Any] else {
            return nil
        }
        self.nameColor = lumenColor(spec["nameColor"])
        let ring = spec["ring"] as? [String: Any]
        self.ringColors = (ring?["colors"] as? [Any] ?? []).compactMap(lumenColor)
        self.ringWidth = lumenCGFloat(ring?["width"]) ?? 2.0
        let tag = spec["tag"] as? [String: Any]
        let text = tag?["text"] as? String
        self.tagText = (text?.isEmpty ?? true) ? nil : text
        self.tagColor = lumenColor(tag?["color"])
        self.badgeImagePath = (spec["badge"] as? [String: Any])?["image"] as? String
    }
}

public struct LumenDecoration {
    public let banner: LumenFill?
    public let background: LumenFill?
    public let avatar: LumenAvatarStyle?
    public let name: LumenNameStyle?
    public let textColor: UIColor?
    public let hintColor: UIColor?
    public let actionColor: UIColor?
    public let blocksColor: UIColor?
    public let thoughtText: String?
    public let thoughtColor: UIColor?
    public let thoughtBackground: UIColor?
    public let soundPath: String?
    public let soundVolume: Float
    public let chat: LumenChatStyle?

    public init(spec: [String: Any]) {
        self.banner = LumenFill(spec["banner"])
        self.background = LumenFill(spec["background"])
        self.avatar = LumenAvatarStyle(spec["avatar"])
        self.name = LumenNameStyle(spec["name"])
        let colors = spec["colors"] as? [String: Any]
        self.textColor = lumenColor(colors?["text"])
        self.hintColor = lumenColor(colors?["hint"])
        self.actionColor = lumenColor(colors?["action"])
        self.blocksColor = lumenColor(colors?["blocks"])
        let thought = spec["thought"] as? [String: Any]
        let text = thought?["text"] as? String
        self.thoughtText = (text?.isEmpty ?? true) ? nil : text
        self.thoughtColor = lumenColor(thought?["color"])
        self.thoughtBackground = lumenColor(thought?["background"])
        let sound = spec["sound"] as? [String: Any]
        let soundPath = sound?["path"] as? String
        self.soundPath = (soundPath?.isEmpty ?? true) ? nil : soundPath
        self.soundVolume = Float(max(0.0, min(1.0, lumenCGFloat(sound?["volume"]) ?? 1.0)))
        self.chat = LumenChatStyle(spec["chat"])
    }

    public var changesPageColors: Bool {
        return self.background != nil || self.blocksColor != nil || self.textColor != nil || self.hintColor != nil || self.actionColor != nil
    }
}

// MARK: Values

/// "#RRGGBB", "#AARRGGBB" or an ARGB integer (as Android stores colors).
public func lumenColor(_ value: Any?) -> UIColor? {
    if let number = value as? NSNumber {
        let argb = UInt32(truncatingIfNeeded: number.int64Value)
        return UIColor(red: CGFloat((argb >> 16) & 0xff) / 255.0, green: CGFloat((argb >> 8) & 0xff) / 255.0, blue: CGFloat(argb & 0xff) / 255.0, alpha: CGFloat((argb >> 24) & 0xff) / 255.0)
    }
    guard var text = value as? String else {
        return nil
    }
    text = text.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") {
        text.removeFirst()
    }
    guard let parsed = UInt32(text, radix: 16) else {
        return nil
    }
    switch text.count {
    case 6:
        return UIColor(red: CGFloat((parsed >> 16) & 0xff) / 255.0, green: CGFloat((parsed >> 8) & 0xff) / 255.0, blue: CGFloat(parsed & 0xff) / 255.0, alpha: 1.0)
    case 8:
        return UIColor(red: CGFloat((parsed >> 16) & 0xff) / 255.0, green: CGFloat((parsed >> 8) & 0xff) / 255.0, blue: CGFloat(parsed & 0xff) / 255.0, alpha: CGFloat((parsed >> 24) & 0xff) / 255.0)
    default:
        return nil
    }
}

func lumenCGFloat(_ value: Any?) -> CGFloat? {
    if let number = value as? NSNumber {
        return CGFloat(number.doubleValue)
    }
    if let text = value as? String, let parsed = Double(text) {
        return CGFloat(parsed)
    }
    return nil
}

// MARK: Drawing helpers shared by the profile and chat renderers

public enum LumenDecorationDrawing {
    private static let imageCache = NSCache<NSString, UIImage>()

    public static func image(path: String) -> UIImage? {
        if let cached = self.imageCache.object(forKey: path as NSString) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        self.imageCache.setObject(image, forKey: path as NSString)
        return image
    }

    /// A view drawing `fill` (image or gradient, alpha, dim, bottom fade) that follows its own
    /// bounds, so callers only set its frame on every layout pass.
    public static func makeView(_ fill: LumenFill) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        let flexible: UIView.AutoresizingMask = [.flexibleWidth, .flexibleHeight]
        let content: UIView
        switch fill.kind {
        case let .color(color):
            content = UIView()
            content.backgroundColor = color
        case let .linearGradient(colors, angle):
            let view = LumenGradientView()
            view.gradientLayer.colors = colors.map(\.cgColor)
            let radians = angle * CGFloat.pi / 180.0
            let dx = cos(radians) / 2.0, dy = sin(radians) / 2.0
            view.gradientLayer.startPoint = CGPoint(x: 0.5 - dx, y: 0.5 - dy)
            view.gradientLayer.endPoint = CGPoint(x: 0.5 + dx, y: 0.5 + dy)
            content = view
        case let .radialGradient(colors, center, radius):
            let view = LumenGradientView()
            view.gradientLayer.type = .radial
            view.gradientLayer.colors = colors.map(\.cgColor)
            view.gradientLayer.startPoint = center
            let extent = max(0.05, radius)
            view.gradientLayer.endPoint = CGPoint(x: center.x + extent, y: center.y + extent)
            content = view
        case let .image(path):
            let view = UIImageView(image: self.image(path: path))
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            content = view
        }
        content.autoresizingMask = flexible
        content.alpha = fill.alpha
        container.addSubview(content)
        if fill.dim > 0.0 {
            let dim = UIView()
            dim.backgroundColor = UIColor(white: 0.0, alpha: fill.dim * fill.alpha)
            dim.autoresizingMask = flexible
            container.addSubview(dim)
        }
        if fill.fade > 0.0 {
            let mask = LumenGradientView()
            mask.gradientLayer.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            mask.gradientLayer.locations = [0.0, NSNumber(value: Double(1.0 - fill.fade)), 1.0]
            mask.autoresizingMask = flexible
            container.mask = mask
        }
        return container
    }

    /// Sets the frame of a view from `makeView`, keeping its fade mask in step.
    public static func layout(_ view: UIView, frame: CGRect) {
        view.frame = frame
        view.mask?.frame = view.bounds
        for subview in view.subviews {
            subview.frame = view.bounds
        }
    }
}

/// A view whose layer is a gradient, so it resizes with the view.
public final class LumenGradientView: UIView {
    override public class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    public var gradientLayer: CAGradientLayer {
        return self.layer as! CAGradientLayer
    }
}
