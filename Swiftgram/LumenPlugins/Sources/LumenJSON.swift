import Foundation

// MARK: Lumen: JSON strings are how Swift and the Python runtime pass everything.

enum LumenJSON {
    static func string(from object: Any?) -> String {
        guard let object, !(object is NSNull) else {
            return "null"
        }
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "null"
    }

    static func object(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}
