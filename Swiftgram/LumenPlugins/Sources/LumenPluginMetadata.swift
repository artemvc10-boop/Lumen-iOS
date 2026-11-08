import Foundation

// MARK: Lumen: the header fields a .plugin declares (__id__, __name__, ...), read from the
// source text without running it.

public struct LumenPluginMetadata: Equatable {
    public let id: String
    public let name: String
    public let author: String
    public let version: String
    public let description: String
    public let icon: String?
    public let minVersion: String?

    public static func parse(source: String, fallbackId: String) -> LumenPluginMetadata {
        var fields: [String: String] = [:]
        let pattern = #"(?m)^__(\w+)__\s*=\s*(?:"""([\s\S]*?)"""|'''([\s\S]*?)'''|"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)')"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = source as NSString
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                let key = ns.substring(with: match.range(at: 1))
                if fields[key] != nil {
                    continue
                }
                for group in 2 ... 5 where match.range(at: group).location != NSNotFound {
                    fields[key] = ns.substring(with: match.range(at: group))
                        .replacingOccurrences(of: "\\n", with: "\n")
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\'", with: "'")
                    break
                }
            }
        }
        let rawId = fields["id"] ?? fallbackId
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var id = String(rawId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        if id.isEmpty {
            id = "plugin"
        }
        return LumenPluginMetadata(
            id: id,
            name: fields["name"] ?? rawId,
            author: fields["author"] ?? "",
            version: fields["version"] ?? "",
            description: fields["description"] ?? "",
            icon: fields["icon"],
            minVersion: fields["min_version"] ?? fields["app_version"]
        )
    }
}

/// A short note shown before installing, so the person sees what a plugin can reach before
/// turning it on. This is a plain summary of which bridge calls the source names, not a
/// security guarantee.
public struct LumenPluginNotes {
    public enum Access: String {
        case network
        case files
        case sending
        case clipboard
        case androidOnly
    }

    public let access: [Access]
    public let willNotRun: Bool

    public static func summarize(source: String) -> LumenPluginNotes {
        var access: [Access] = []
        func uses(_ needle: String) -> Bool {
            return source.range(of: needle) != nil
        }
        if uses("requests") || uses("urlopen") || uses("http") || uses("Lumen.fetch") {
            access.append(.network)
        }
        if uses("open(") || uses("os.remove") || uses("shutil") || uses("write_file") || uses("read_file") {
            access.append(.files)
        }
        if uses("send_message") || uses("send_photo") || uses("send_document") || uses("send_video") || uses("sendMessage") {
            access.append(.sending)
        }
        if uses("copy_to_clipboard") || uses("clipboard") {
            access.append(.clipboard)
        }
        if uses("hook_method") || uses("hook_all_methods") || uses("find_class") || uses("XposedBridge") {
            access.append(.androidOnly)
        }
        // Skulpt does not support these; a plugin that needs them will not load.
        let willNotRun = uses("nonlocal ") || uses(":=")
        return LumenPluginNotes(access: access, willNotRun: willNotRun)
    }
}
