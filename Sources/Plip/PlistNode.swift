import Foundation
import CoreFoundation

enum PlistKind: String, CaseIterable {
    case dictionary = "Dictionary", array = "Array", string = "String"
    case integer = "Integer", real = "Real", boolean = "Boolean", date = "Date", data = "Data"

    var isContainer: Bool { self == .dictionary || self == .array }
    var symbol: String {
        switch self {
        case .dictionary: return "curlybraces"
        case .array: return "square.stack"
        case .string: return "textformat"
        case .integer, .real: return "number"
        case .boolean: return "switch.2"
        case .date: return "calendar"
        case .data: return "externaldrive"
        }
    }
}

enum PlistError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

final class PlistNode: NSObject {
    let id: UUID
    var key: String
    var kind: PlistKind
    var scalar: Any
    var children: [PlistNode]
    weak var parent: PlistNode?

    init(key: String, kind: PlistKind, scalar: Any = "", children: [PlistNode] = [], id: UUID = UUID()) {
        self.id = id
        self.key = key; self.kind = kind; self.scalar = scalar; self.children = children
        super.init()
        for child in children { child.parent = self }
    }

    static func empty(_ kind: PlistKind, key: String = "New Item") -> PlistNode {
        let value: Any
        switch kind {
        case .dictionary, .array, .string: value = ""
        case .integer: value = NSNumber(value: Int64(0))
        case .real: value = NSNumber(value: 0.0)
        case .boolean: value = false
        case .date: value = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        case .data: value = Data()
        }
        return PlistNode(key: key, kind: kind, scalar: value)
    }

    static func decode(_ object: Any, key: String = "Root") throws -> PlistNode {
        if let dictionary = object as? [String: Any] {
            return try PlistNode(key: key, kind: .dictionary, children: dictionary.keys.sorted().map {
                try decode(dictionary[$0]!, key: $0)
            })
        }
        if let array = object as? [Any] {
            return try PlistNode(key: key, kind: .array, children: array.map { try decode($0, key: "") })
        }
        let kind: PlistKind
        if object is String { kind = .string }
        else if object is Date { kind = .date }
        else if object is Data { kind = .data }
        else if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { kind = .boolean }
            else if CFNumberIsFloatType(unsafeBitCast(number, to: CFNumber.self)) { kind = .real }
            else { kind = .integer }
        } else { throw PlistError.invalid("This file contains an unsupported property list value.") }
        return PlistNode(key: key, kind: kind, scalar: object)
    }

    func object() -> Any {
        switch kind {
        case .dictionary: return Dictionary(uniqueKeysWithValues: children.map { ($0.key, $0.object()) })
        case .array: return children.map { $0.object() }
        default: return scalar
        }
    }

    func copyTree(preservingIdentity: Bool = true) -> PlistNode {
        PlistNode(key: key, kind: kind, scalar: scalar, children: children.map { $0.copyTree(preservingIdentity: preservingIdentity) }, id: preservingIdentity ? id : UUID())
    }

    var displayKey: String {
        guard let parent else { return "Root" }
        return parent.kind == .array ? "Item \(parent.children.firstIndex(where: { $0 === self }) ?? 0)" : key
    }

    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    var text: String {
        switch kind {
        case .dictionary, .array: return "\(children.count) \(children.count == 1 ? "item" : "items")"
        case .boolean: return (scalar as? Bool == true) ? "true" : "false"
        case .date: return Self.dateFormatter.string(from: scalar as! Date)
        case .data: return (scalar as! Data).map { String(format: "%02X", $0) }.joined(separator: " ")
        case .integer, .real: return (scalar as! NSNumber).stringValue
        default: return scalar as? String ?? ""
        }
    }

    static func parse(_ text: String, as kind: PlistKind) throws -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .string: return text
        case .integer:
            if let value = Int64(trimmed) { return NSNumber(value: value) }
            if let value = UInt64(trimmed) { return NSNumber(value: value) }
            throw PlistError.invalid("Enter a whole number between −9223372036854775808 and 18446744073709551615.")
        case .real:
            guard let value = Double(trimmed), value.isFinite else { throw PlistError.invalid("Enter a finite decimal number, such as 3.14 or 1.5e3.") }
            return NSNumber(value: value)
        case .boolean:
            guard ["true", "false"].contains(trimmed.lowercased()) else { throw PlistError.invalid("A Boolean value must be true or false.") }
            return trimmed.lowercased() == "true"
        case .date:
            guard let value = dateFormatter.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed) else {
                throw PlistError.invalid("Enter an ISO 8601 date with a time zone, such as 2026-01-01T12:00:00Z.")
            }
            return value
        case .data:
            let compact = text.filter { !$0.isWhitespace }
            guard compact.count.isMultiple(of: 2), compact.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                throw PlistError.invalid("Enter pairs of hexadecimal digits, such as DE AD BE EF. Whitespace is allowed.")
            }
            var bytes = Data()
            var position = compact.startIndex
            while position < compact.endIndex {
                let next = compact.index(position, offsetBy: 2)
                bytes.append(UInt8(compact[position..<next], radix: 16)!)
                position = next
            }
            return bytes
        case .dictionary, .array: return ""
        }
    }

    func availableKey(_ proposed: String) -> String {
        let keys = Set(children.map(\.key))
        if !keys.contains(proposed) { return proposed }
        var suffix = 2
        while keys.contains("\(proposed) \(suffix)") { suffix += 1 }
        return "\(proposed) \(suffix)"
    }

    var descendantCount: Int { children.reduce(0) { $0 + 1 + $1.descendantCount } }
}
