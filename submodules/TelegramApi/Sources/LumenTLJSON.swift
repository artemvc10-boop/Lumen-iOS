import Foundation
import TelegramApiObjC

// MARK: Lumen

/// Converts TL objects to JSON-compatible values and back, driven by the schema table, so
/// plugins can read and rewrite any request, response or update without per-type code.
///
/// Shape: an object is `{"_": "constructorName", "field": value, ...}` with the schema's
/// field names (`random_id`, as on Android). `int` and `double` are numbers, `long` is
/// `{"#l": "decimal"}` (JavaScript numbers would lose precision), `bytes` is
/// `{"#b": "base64"}`, `int256` is `{"#i256": [a, b, c, d]}` with each part as `{"#l": ...}`,
/// `Bool` is `true`/`false`, vectors are arrays. Fields behind an unset flag are left out.
/// When encoding, the bits of `flags` fields that guard a value follow whether that value is
/// present; bits of `true` flags (which have no field) are taken from the given number.
public enum LumenTLJSON {
    private static let vectorId: Int32 = 481674261
    private static let boolTrueId: Int32 = -1720552011
    private static let boolFalseId: Int32 = -1132882121

    private struct DecodeError: Error {}

    // MARK: Name lookup

    private static let tables: (constructors: [String: UnsafePointer<TLConstructorInfo>], functions: [String: UnsafePointer<TLFunctionInfo>], functionIds: [Int32: UnsafePointer<TLFunctionInfo>]) = {
        var constructors: [String: UnsafePointer<TLConstructorInfo>] = [:]
        var index: UInt32 = 0
        while index < TLApiConstructorCount {
            let info = TLApiConstructorAt(index)
            constructors[String(cString: info.pointee.name)] = info
            index += 1
        }
        var functions: [String: UnsafePointer<TLFunctionInfo>] = [:]
        var functionIds: [Int32: UnsafePointer<TLFunctionInfo>] = [:]
        index = 0
        while index < TLApiFunctionCount {
            let info = TLApiFunctionAt(index)
            functions[String(cString: info.pointee.constructor.name)] = info
            functionIds[Int32(bitPattern: info.pointee.constructor.constructorId)] = info
            index += 1
        }
        return (constructors, functions, functionIds)
    }()

    /// `constructor` is the first member of TLFunctionInfo (TLObjectFunctionInfo relies on it too).
    private static func functionConstructor(_ info: UnsafePointer<TLFunctionInfo>) -> UnsafePointer<TLConstructorInfo> {
        return UnsafeRawPointer(info).assumingMemoryBound(to: TLConstructorInfo.self)
    }

    // MARK: Public entry points

    /// The function call in a serialized request (as built by `Api.functions.*`).
    public static func decodeFunction(_ buffer: Buffer) -> [String: Any]? {
        let reader = Reader(buffer.makeData())
        guard let id = try? reader.int32(), let info = self.tables.functionIds[id] else {
            return nil
        }
        return try? self.decodeBody(reader, self.functionConstructor(info))
    }

    /// Serializes a function call; nil when it does not fit the schema or names another function.
    public static func encodeFunction(_ json: [String: Any], expectedName: String) -> Buffer? {
        guard let name = json["_"] as? String, name == expectedName, let info = self.tables.functions[name] else {
            return nil
        }
        let writer = Writer()
        let constructor = self.functionConstructor(info)
        writer.int32(Int32(bitPattern: constructor.pointee.constructorId))
        guard (try? self.encodeBody(writer, constructor, json)) != nil else {
            return nil
        }
        return Buffer(data: writer.data)
    }

    /// A ready-to-send call built from JSON, for plugins' own requests (send_request).
    public static func functionCall(_ json: [String: Any]) -> (FunctionDescription, Buffer, DeserializeFunctionResponse<Any>)? {
        guard let name = json["_"] as? String, let info = self.tables.functions[name], let buffer = self.encodeFunction(json, expectedName: name) else {
            return nil
        }
        return (FunctionDescription(name: name, parameters: []), buffer, DeserializeFunctionResponse { buffer in
            return tlParseFunctionResult(buffer, info)
        })
    }

    /// A parsed API value (`Api.Update`, a function result, ...) as JSON.
    public static func encodeValue(_ value: Any) -> Any? {
        if let backed = value as? TLObjectBacked {
            let reader = Reader(tlSerializedData(backed.tlBackingObject, boxed: true))
            return try? self.decodeBoxed(reader)
        }
        if let values = value as? [Int32] {
            return values.map { NSNumber(value: $0) }
        }
        if let values = value as? [Int64] {
            return values.map { ["#l": String($0)] }
        }
        if let values = value as? [String] {
            return values
        }
        if let values = value as? [Any] {
            var result: [Any] = []
            for element in values {
                guard let encoded = self.encodeValue(element) else {
                    return nil
                }
                result.append(encoded)
            }
            return result
        }
        return nil
    }

    /// The boxed serialization of a JSON object, for parsing back into an API value.
    public static func encodeObject(_ json: [String: Any]) -> Buffer? {
        let writer = Writer()
        guard (try? self.encodeBoxed(writer, json, typeIndex: nil)) != nil else {
            return nil
        }
        return Buffer(data: writer.data)
    }

    /// Parses a JSON object back into an API value (e.g. an `Api.Update`).
    public static func parseObject(_ json: [String: Any]) -> Any? {
        guard let buffer = self.encodeObject(json) else {
            return nil
        }
        let reader = BufferReader(buffer)
        guard let signature = reader.readInt32() else {
            return nil
        }
        return tlParseTopLevel(reader, signature: signature)
    }

    /// The name of a value's constructor (`updateUserTyping`), without converting it.
    public static func constructorName(_ value: Any) -> String? {
        guard let backed = value as? TLObjectBacked else {
            return nil
        }
        return String(cString: backed.tlBackingObject.tl_constructorInfo.pointee.name)
    }

    /// Whether the constructor carries a `pts` (dropping such an update would leave a gap
    /// in the update sequence).
    public static func constructorHasPts(_ name: String) -> Bool {
        guard let info = self.tables.constructors[name], let fields = info.pointee.fields else {
            return false
        }
        for index in 0 ..< Int(info.pointee.fieldCount) where String(cString: fields[index].name) == "pts" {
            return true
        }
        return false
    }

    public static func jsonString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public static func jsonObject(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }

    // MARK: Decoding

    private final class Reader {
        let bytes: [UInt8]
        var offset = 0

        init(_ data: Data) {
            self.bytes = [UInt8](data)
        }

        func raw(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, self.offset + count <= self.bytes.count else {
                throw DecodeError()
            }
            let slice = self.bytes[self.offset ..< self.offset + count]
            self.offset += count
            return slice
        }

        func int32() throws -> Int32 {
            var value: UInt32 = 0
            for (shift, byte) in try self.raw(4).enumerated() {
                value |= UInt32(byte) << UInt32(shift * 8)
            }
            return Int32(bitPattern: value)
        }

        func int64() throws -> Int64 {
            var value: UInt64 = 0
            for (shift, byte) in try self.raw(8).enumerated() {
                value |= UInt64(byte) << UInt64(shift * 8)
            }
            return Int64(bitPattern: value)
        }

        func double() throws -> Double {
            return Double(bitPattern: UInt64(bitPattern: try self.int64()))
        }

        func bytesValue() throws -> Data {
            let first = Int(try self.raw(1).first!)
            let count: Int
            let header: Int
            if first == 254 {
                let length = try self.raw(3)
                count = Int(length[length.startIndex]) | (Int(length[length.startIndex + 1]) << 8) | (Int(length[length.startIndex + 2]) << 16)
                header = 4
            } else {
                count = first
                header = 1
            }
            let data = Data(try self.raw(count))
            let total = header + count
            let padding = (4 - total % 4) % 4
            _ = try self.raw(padding)
            return data
        }
    }

    private static func long(_ value: Int64) -> [String: Any] {
        return ["#l": String(value)]
    }

    private static func decodeBoxed(_ reader: Reader) throws -> Any {
        let id = try reader.int32()
        if id == self.boolTrueId {
            return true
        }
        if id == self.boolFalseId {
            return false
        }
        guard let info = TLApiConstructorWithId(id) else {
            throw DecodeError()
        }
        return try self.decodeBody(reader, info)
    }

    private static func bareInfo(_ field: TLFieldInfo) -> UnsafePointer<TLConstructorInfo> {
        return TLApiTypeAt(UInt32(field.typeIndex)).pointee.constructors[Int(field.constructorIndex)]
    }

    private static func decodeBody(_ reader: Reader, _ info: UnsafePointer<TLConstructorInfo>) throws -> [String: Any] {
        var result: [String: Any] = ["_": String(cString: info.pointee.name)]
        guard let fields = info.pointee.fields else {
            return result
        }
        let count = Int(info.pointee.fieldCount)
        var ints: [Int: UInt32] = [:]
        for index in 0 ..< count {
            let field = fields[index]
            if field.flagsFieldIndex >= 0 {
                let flags = ints[Int(field.flagsFieldIndex)] ?? 0
                if flags & (UInt32(1) << UInt32(field.flagBit)) == 0 {
                    continue
                }
            }
            let name = String(cString: field.name)
            switch field.kind {
            case .int32:
                let value = try reader.int32()
                ints[index] = UInt32(bitPattern: value)
                result[name] = NSNumber(value: value)
            case .object:
                if field.isBareObject != 0 {
                    result[name] = try self.decodeBody(reader, self.bareInfo(field))
                } else {
                    result[name] = try self.decodeBoxed(reader)
                }
            case .vector:
                if field.isBoxedVector != 0 {
                    _ = try reader.int32()
                }
                let elements = Int(try reader.int32())
                guard elements >= 0, elements <= reader.bytes.count else {
                    throw DecodeError()
                }
                var array: [Any] = []
                array.reserveCapacity(elements)
                for _ in 0 ..< elements {
                    array.append(try self.decodeScalar(reader, field.elementKind, field))
                }
                result[name] = array
            default:
                result[name] = try self.decodeScalar(reader, field.kind, field)
            }
        }
        return result
    }

    private static func decodeScalar(_ reader: Reader, _ kind: TLFieldKind, _ field: TLFieldInfo) throws -> Any {
        switch kind {
        case .int32:
            return NSNumber(value: try reader.int32())
        case .int64:
            return self.long(try reader.int64())
        case .double:
            return NSNumber(value: try reader.double())
        case .int256:
            var parts: [Any] = []
            for _ in 0 ..< 4 {
                parts.append(self.long(try reader.int64()))
            }
            return ["#i256": parts]
        case .string:
            let data = try reader.bytesValue()
            return String(data: data, encoding: .utf8) ?? ""
        case .bytes:
            return ["#b": try reader.bytesValue().base64EncodedString()]
        case .object:
            if field.isBareObject != 0 {
                return try self.decodeBody(reader, self.bareInfo(field))
            }
            return try self.decodeBoxed(reader)
        case .vector:
            throw DecodeError()
        }
    }

    // MARK: Encoding

    private final class Writer {
        var data = Data()

        func int32(_ value: Int32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { self.data.append(contentsOf: $0) }
        }

        func int64(_ value: Int64) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { self.data.append(contentsOf: $0) }
        }

        func double(_ value: Double) {
            self.int64(Int64(bitPattern: value.bitPattern))
        }

        func bytes(_ value: Data) {
            let count = value.count
            let header: Int
            if count >= 254 {
                self.data.append(contentsOf: [254, UInt8(count & 0xff), UInt8((count >> 8) & 0xff), UInt8((count >> 16) & 0xff)])
                header = 4
            } else {
                self.data.append(UInt8(count))
                header = 1
            }
            self.data.append(value)
            let padding = (4 - (header + count) % 4) % 4
            if padding > 0 {
                self.data.append(contentsOf: [UInt8](repeating: 0, count: padding))
            }
        }
    }

    private static func isPresent(_ value: Any?) -> Bool {
        guard let value else {
            return false
        }
        return !(value is NSNull)
    }

    private static func int64Value(_ value: Any?) throws -> Int64 {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let dict = value as? [String: Any], let text = dict["#l"] as? String, let parsed = Int64(text) {
            return parsed
        }
        if let text = value as? String, let parsed = Int64(text) {
            return parsed
        }
        throw DecodeError()
    }

    private static func encodeBoxed(_ writer: Writer, _ value: Any, typeIndex: UInt16?) throws {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            writer.int32(number.boolValue ? self.boolTrueId : self.boolFalseId)
            return
        }
        guard let json = value as? [String: Any], let name = json["_"] as? String, let info = self.tables.constructors[name] else {
            throw DecodeError()
        }
        if let typeIndex, info.pointee.typeIndex != typeIndex {
            throw DecodeError()
        }
        writer.int32(Int32(bitPattern: info.pointee.constructorId))
        try self.encodeBody(writer, info, json)
    }

    private static func encodeBody(_ writer: Writer, _ info: UnsafePointer<TLConstructorInfo>, _ json: [String: Any]) throws {
        guard let fields = info.pointee.fields else {
            return
        }
        let count = Int(info.pointee.fieldCount)
        // Flags fields: keep the given bits (true flags live there), then make every bit that
        // guards a value match whether that value is present.
        var flags: [Int: UInt32] = [:]
        for index in 0 ..< count {
            let field = fields[index]
            guard field.flagsFieldIndex >= 0 else {
                continue
            }
            let flagsIndex = Int(field.flagsFieldIndex)
            if flags[flagsIndex] == nil {
                let given = json[String(cString: fields[flagsIndex].name)]
                var initial: UInt32 = 0
                if self.isPresent(given) {
                    initial = UInt32(truncatingIfNeeded: try self.int64Value(given))
                }
                flags[flagsIndex] = initial
            }
            let bit = UInt32(1) << UInt32(field.flagBit)
            if self.isPresent(json[String(cString: field.name)]) {
                flags[flagsIndex]! |= bit
            } else {
                flags[flagsIndex]! &= ~bit
            }
        }
        for index in 0 ..< count {
            let field = fields[index]
            let name = String(cString: field.name)
            if let flagsValue = flags[index] {
                writer.int32(Int32(bitPattern: flagsValue))
                continue
            }
            if field.flagsFieldIndex >= 0 {
                let current = flags[Int(field.flagsFieldIndex)] ?? 0
                if current & (UInt32(1) << UInt32(field.flagBit)) == 0 {
                    continue
                }
            }
            let value = json[name]
            guard self.isPresent(value) else {
                // A flags field that only holds `true` flags may be left out of a new object.
                if field.kind == .int32 && name.hasPrefix("flags") {
                    writer.int32(0)
                    continue
                }
                throw DecodeError()
            }
            if field.kind == .vector {
                guard let array = value as? [Any] else {
                    throw DecodeError()
                }
                if field.isBoxedVector != 0 {
                    writer.int32(self.vectorId)
                }
                writer.int32(Int32(array.count))
                for element in array {
                    try self.encodeScalar(writer, element, field.elementKind, field)
                }
            } else {
                try self.encodeScalar(writer, value!, field.kind, field)
            }
        }
    }

    private static func encodeScalar(_ writer: Writer, _ value: Any, _ kind: TLFieldKind, _ field: TLFieldInfo) throws {
        switch kind {
        case .int32:
            writer.int32(Int32(truncatingIfNeeded: try self.int64Value(value)))
        case .int64:
            writer.int64(try self.int64Value(value))
        case .double:
            guard let number = value as? NSNumber else {
                throw DecodeError()
            }
            writer.double(number.doubleValue)
        case .int256:
            guard let dict = value as? [String: Any], let parts = dict["#i256"] as? [Any], parts.count == 4 else {
                throw DecodeError()
            }
            for part in parts {
                writer.int64(try self.int64Value(part))
            }
        case .string:
            guard let text = value as? String else {
                throw DecodeError()
            }
            writer.bytes(text.data(using: .utf8) ?? Data())
        case .bytes:
            if let dict = value as? [String: Any], let text = dict["#b"] as? String, let data = Data(base64Encoded: text) {
                writer.bytes(data)
            } else if let text = value as? String {
                writer.bytes(text.data(using: .utf8) ?? Data())
            } else {
                throw DecodeError()
            }
        case .object:
            if field.isBareObject != 0 {
                guard let json = value as? [String: Any] else {
                    throw DecodeError()
                }
                try self.encodeBody(writer, self.bareInfo(field), json)
            } else {
                try self.encodeBoxed(writer, value, typeIndex: field.typeIndex)
            }
        case .vector:
            throw DecodeError()
        }
    }
}
