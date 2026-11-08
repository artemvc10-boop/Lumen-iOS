import Foundation
import Compression

// MARK: Lumen: a small ZIP reader and writer (stored and deflate entries), enough for
// plugin archives and the meme library's export, which must open in Android's zipfile.

public enum LumenZipError: Error {
    case notAZip
    case unsupportedMethod
    case corrupt
}

private let crcTable: [UInt32] = (0 ..< 256).map { index -> UInt32 in
    var value = UInt32(index)
    for _ in 0 ..< 8 {
        value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
    }
    return value
}

func lumenCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFFFFFF
    data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
        for byte in buffer {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }
    return crc ^ 0xFFFFFFFF
}

/// Raw DEFLATE (RFC 1951): what Compression calls COMPRESSION_ZLIB.
private func deflate(_ data: Data) -> Data? {
    if data.isEmpty {
        return nil
    }
    let capacity = data.count + data.count / 10 + 1024
    var output = Data(count: capacity)
    let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
        return data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Int in
            return compression_encode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, capacity, input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
    }
    if written == 0 || written >= data.count {
        return nil
    }
    output.count = written
    return output
}

private func inflate(_ data: Data, size: Int) -> Data? {
    if size == 0 {
        return Data()
    }
    var output = Data(count: size)
    let written = output.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) -> Int in
        return data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Int in
            return compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size, input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
    }
    if written != size {
        return nil
    }
    return output
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }

    mutating func appendLE32(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }

    func le16(_ offset: Int) -> Int {
        guard offset + 2 <= self.count else {
            return 0
        }
        let base = self.startIndex + offset
        return Int(self[base]) | Int(self[base + 1]) << 8
    }

    func le32(_ offset: Int) -> Int {
        guard offset + 4 <= self.count else {
            return 0
        }
        let base = self.startIndex + offset
        return Int(self[base]) | Int(self[base + 1]) << 8 | Int(self[base + 2]) << 16 | Int(self[base + 3]) << 24
    }
}

public final class LumenZipWriter {
    private var body = Data()
    private var central = Data()
    private var count = 0

    public init() {
    }

    public func add(name: String, data: Data) {
        let nameData = Data(name.utf8)
        let crc = lumenCRC32(data)
        let compressed = deflate(data)
        let method: UInt16 = compressed == nil ? 0 : 8
        let payload = compressed ?? data
        let offset = UInt32(self.body.count)

        // DOS time/date for 1980-01-01 00:00.
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1

        self.body.appendLE32(0x04034b50)
        self.body.appendLE16(20)
        self.body.appendLE16(0x0800) // UTF-8 names
        self.body.appendLE16(method)
        self.body.appendLE16(dosTime)
        self.body.appendLE16(dosDate)
        self.body.appendLE32(crc)
        self.body.appendLE32(UInt32(payload.count))
        self.body.appendLE32(UInt32(data.count))
        self.body.appendLE16(UInt16(nameData.count))
        self.body.appendLE16(0)
        self.body.append(nameData)
        self.body.append(payload)

        self.central.appendLE32(0x02014b50)
        self.central.appendLE16(20)
        self.central.appendLE16(20)
        self.central.appendLE16(0x0800)
        self.central.appendLE16(method)
        self.central.appendLE16(dosTime)
        self.central.appendLE16(dosDate)
        self.central.appendLE32(crc)
        self.central.appendLE32(UInt32(payload.count))
        self.central.appendLE32(UInt32(data.count))
        self.central.appendLE16(UInt16(nameData.count))
        self.central.appendLE16(0)
        self.central.appendLE16(0)
        self.central.appendLE16(0)
        self.central.appendLE16(0)
        self.central.appendLE32(0)
        self.central.appendLE32(offset)
        self.central.append(nameData)
        self.count += 1
    }

    public func finish() -> Data {
        var result = self.body
        let centralOffset = UInt32(result.count)
        result.append(self.central)
        result.appendLE32(0x06054b50)
        result.appendLE16(0)
        result.appendLE16(0)
        result.appendLE16(UInt16(self.count))
        result.appendLE16(UInt16(self.count))
        result.appendLE32(UInt32(self.central.count))
        result.appendLE32(centralOffset)
        result.appendLE16(0)
        return result
    }
}

public final class LumenZipReader {
    public struct Entry {
        public let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let localOffset: Int
    }

    private let data: Data
    public let entries: [Entry]

    public init(data: Data) throws {
        self.data = data
        // Find the end of central directory record (it ends the file, up to a 64 KB comment).
        var eocd = -1
        if data.count >= 22 {
            var index = data.count - 22
            let lowest = max(0, data.count - 22 - 65535)
            while index >= lowest {
                if data.le32(index) == 0x06054b50 {
                    eocd = index
                    break
                }
                index -= 1
            }
        }
        if eocd < 0 {
            throw LumenZipError.notAZip
        }
        let total = data.le16(eocd + 10)
        var offset = data.le32(eocd + 16)
        var entries: [Entry] = []
        for _ in 0 ..< total {
            guard data.le32(offset) == 0x02014b50 else {
                throw LumenZipError.corrupt
            }
            let method = data.le16(offset + 10)
            let compressedSize = data.le32(offset + 20)
            let size = data.le32(offset + 24)
            let nameLength = data.le16(offset + 28)
            let extraLength = data.le16(offset + 30)
            let commentLength = data.le16(offset + 32)
            let localOffset = data.le32(offset + 42)
            let start = data.startIndex + offset + 46
            guard start + nameLength <= data.endIndex else {
                throw LumenZipError.corrupt
            }
            let name = String(decoding: data[start ..< start + nameLength], as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressedSize, size: size, localOffset: localOffset))
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    public func read(_ entry: Entry) throws -> Data {
        let local = entry.localOffset
        guard self.data.le32(local) == 0x04034b50 else {
            throw LumenZipError.corrupt
        }
        let start = local + 30 + self.data.le16(local + 26) + self.data.le16(local + 28)
        guard start + entry.compressedSize <= self.data.count else {
            throw LumenZipError.corrupt
        }
        let base = self.data.startIndex + start
        let payload = self.data[base ..< base + entry.compressedSize]
        switch entry.method {
        case 0:
            return Data(payload)
        case 8:
            guard let result = inflate(Data(payload), size: entry.size) else {
                throw LumenZipError.corrupt
            }
            return result
        default:
            throw LumenZipError.unsupportedMethod
        }
    }

    public func read(name: String) throws -> Data? {
        guard let entry = self.entries.first(where: { $0.name == name }) else {
            return nil
        }
        return try self.read(entry)
    }

    /// Extracts entries below `directory`, refusing names that would escape it.
    public func extract(to directory: URL, only names: Set<String>? = nil) throws {
        let root = directory.standardizedFileURL.path
        for entry in self.entries {
            if let names, !names.contains(entry.name) {
                continue
            }
            let target = directory.appendingPathComponent(entry.name).standardizedFileURL
            guard target.path.hasPrefix(root) else {
                continue
            }
            if entry.name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try self.read(entry).write(to: target)
        }
    }
}
