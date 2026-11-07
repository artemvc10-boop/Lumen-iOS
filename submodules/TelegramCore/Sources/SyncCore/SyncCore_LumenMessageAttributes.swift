import Foundation
import Postbox

// MARK: Lumen

/// The message was deleted on the server; Lumen keeps the local copy.
public final class LumenDeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

/// Earlier versions of an edited message, oldest first.
public final class LumenEditHistoryAttribute: MessageAttribute {
    public struct Entry: Equatable {
        public let text: String
        /// When this version stopped being current, i.e. the date of the edit that replaced it.
        public let date: Int32

        public init(text: String, date: Int32) {
            self.text = text
            self.date = date
        }
    }

    /// Long-lived chats can collect many edits; keep the database row bounded.
    public static let maxEntries = 50

    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = Array(entries.suffix(LumenEditHistoryAttribute.maxEntries))
    }

    required public init(decoder: PostboxDecoder) {
        let texts = decoder.decodeStringArrayForKey("t")
        let dates = decoder.decodeInt32ArrayForKey("d")
        self.entries = zip(texts, dates).map { Entry(text: $0, date: $1) }
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeStringArray(self.entries.map(\.text), forKey: "t")
        encoder.encodeInt32Array(self.entries.map(\.date), forKey: "d")
    }
}

/// The media arrived as view-once / self-destructing; Lumen kept it as ordinary media.
public final class LumenViewOnceMessageAttribute: MessageAttribute {
    public let timeout: Int32

    public init(timeout: Int32) {
        self.timeout = timeout
    }

    required public init(decoder: PostboxDecoder) {
        self.timeout = decoder.decodeInt32ForKey("t", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.timeout, forKey: "t")
    }
}

public extension Message {
    var lumenDeletedDate: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? LumenDeletedMessageAttribute {
                return attribute.date
            }
        }
        return nil
    }

    var lumenIsKeptViewOnce: Bool {
        return self.attributes.contains(where: { $0 is LumenViewOnceMessageAttribute })
    }

    var lumenEditHistory: [LumenEditHistoryAttribute.Entry] {
        for attribute in self.attributes {
            if let attribute = attribute as? LumenEditHistoryAttribute {
                return attribute.entries
            }
        }
        return []
    }
}
