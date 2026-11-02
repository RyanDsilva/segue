import Foundation

// Forward compatibility for Segue's JSON files (docs/architecture/data-compatibility.md):
// a key this build does not know, or a known key whose value it cannot read (an enum case
// added later, a reshaped value), is kept verbatim and written back on the next save, so a
// load, edit and save never drops what another Segue or another tool wrote.

/// Any JSON value, kept verbatim. Integers stay integers (`5`, not `5.0`).
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([Self])
    case object([String: Self])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: Self].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

/// A coding key for any string: reads every key of an object, writes kept ones back.
public struct AnyCodingKey: CodingKey, Hashable, Sendable {
    public let stringValue: String

    public init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    public init(stringValue: String) {
        self.stringValue = stringValue
    }

    public var intValue: Int? {
        nil
    }

    public init?(intValue _: Int) {
        nil
    }
}

/// The keys of one JSON object that its Swift type does not model (or could not read), kept
/// verbatim for the next save.
///
/// A type that carries one reads its object through `LenientObject`, and its `encode(to:)`
/// calls `encode(to:)` here **first**: a key the type then writes itself replaces the kept
/// raw value of the same name, so a value the user set always wins, and a known key the type
/// leaves out (nil) keeps the raw value it could not read.
///
/// Kept keys are not part of a value's identity: two values that differ only in what they
/// kept compare equal (`==` is always true and hashing adds nothing), so `prefs == .init()`
/// still means "the defaults" and no change check reacts to keys the app cannot show. Compare
/// `values` to test what was kept.
public struct UnknownFields: Sendable, Hashable {
    public private(set) var values: [String: JSONValue]
    /// Elements of a known array this build could not read, by key, kept to be written back
    /// after the readable ones (`appending(_:to:)`), so one unreadable cue or part is never
    /// deleted by a save.
    public private(set) var unreadableElements: [String: [JSONValue]]

    public init(
        _ values: [String: JSONValue] = [:],
        unreadableElements: [String: [JSONValue]] = [:],
    ) {
        self.values = values
        self.unreadableElements = unreadableElements
    }

    /// No kept keys.
    public static let empty = Self()

    public var isEmpty: Bool {
        values.isEmpty && unreadableElements.isEmpty
    }

    /// The kept keys, sorted.
    public var keys: [String] {
        values.keys.sorted()
    }

    public subscript(key: String) -> JSONValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public static func == (_: Self, _: Self) -> Bool {
        true
    }

    public func hash(into _: inout Hasher) {}

    /// Writes every kept key into the object `encoder` is writing.
    public func encode(to encoder: any Encoder) throws {
        guard !values.isEmpty else { return }
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in values {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
    }

    /// Every key of the object `decoder` holds that is not in `known` or `retired`.
    /// `retired` names keys a migration or a ruling removed on purpose: they are dropped
    /// (not written back) instead of kept.
    public init(from decoder: any Decoder, known: Set<String>, retired: Set<String> = []) {
        unreadableElements = [:]
        guard let container = try? decoder.container(keyedBy: AnyCodingKey.self) else {
            values = [:]
            return
        }
        var values: [String: JSONValue] = [:]
        for key in container.allKeys
            where !known.contains(key.stringValue) && !retired.contains(key.stringValue)
        {
            values[key.stringValue] = try? container.decode(JSONValue.self, forKey: key)
        }
        self.values = values
    }

    /// `values` followed by the unreadable elements kept for `key`, to encode as that key's
    /// array.
    public func appending<T: Encodable>(_ values: [T], to key: String) -> KeptArray<T> {
        KeptArray(values: values, kept: unreadableElements[key] ?? [])
    }

    mutating func keepUnreadable(_ elements: [JSONValue], for key: String) {
        unreadableElements[key] = elements.isEmpty ? nil : elements
    }
}

/// An array's readable values followed by the raw elements kept beside them.
public struct KeptArray<T: Encodable>: Encodable {
    let values: [T]
    let kept: [JSONValue]

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in values {
            try container.encode(value)
        }
        for value in kept {
            try container.encode(value)
        }
    }
}

/// Reads one JSON object field by field and leniently: a missing or unreadable field takes
/// its fallback instead of failing the object, and an unreadable one is kept raw in
/// `unknown` (with every key `Key` does not name), to be written back on save.
///
/// ```swift
/// var object = try LenientObject<CodingKeys>(decoder)
/// tags = object.value(.tags) ?? []
/// unknown = object.unknown
/// ```
public struct LenientObject<Key: CodingKey & CaseIterable> {
    public let container: KeyedDecodingContainer<Key>
    private let raw: KeyedDecodingContainer<AnyCodingKey>?
    /// The unknown keys plus the known ones that failed to decode so far.
    public private(set) var unknown: UnknownFields

    /// `retired` keys (removed on purpose) are neither modelled nor kept.
    public init(_ decoder: any Decoder, retired: Set<String> = []) throws {
        container = try decoder.container(keyedBy: Key.self)
        raw = try? decoder.container(keyedBy: AnyCodingKey.self)
        unknown = UnknownFields(
            from: decoder,
            known: Set(Key.allCases.map(\.stringValue)),
            retired: retired,
        )
    }

    /// The value at `key`, or nil when it is absent, null or unreadable (an unreadable value
    /// is kept raw).
    public mutating func value<T: Decodable>(_ key: Key) -> T? {
        do {
            return try container.decodeIfPresent(T.self, forKey: key)
        } catch {
            keepRaw(key)
            return nil
        }
    }

    /// The value at `key`, or `fallback` when it is absent, null or unreadable.
    public mutating func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        value(key) ?? fallback
    }

    /// The value at `key`; throws when it is absent or unreadable (identity fields).
    public func required<T: Decodable>(_ key: Key) throws -> T {
        try container.decode(T.self, forKey: key)
    }

    /// The array at `key` read element by element: an unreadable element is left out of the
    /// result and kept raw (`UnknownFields.appending(_:to:)` writes it back after the
    /// readable ones). Nil when the key is absent or null; a value that is not an array is
    /// kept raw.
    public mutating func elements<T: Decodable>(_ key: Key) -> [T]? {
        guard let lenient = try? container.decodeIfPresent([Element<T>].self, forKey: key) else {
            if container.contains(key), (try? container.decodeNil(forKey: key)) != true {
                keepRaw(key)
            }
            return nil
        }
        unknown.keepUnreadable(lenient.compactMap(\.raw), for: key.stringValue)
        return lenient.compactMap(\.value)
    }

    private mutating func keepRaw(_ key: Key) {
        let rawKey = AnyCodingKey(key.stringValue)
        if let value = try? raw?.decode(JSONValue.self, forKey: rawKey) {
            unknown[key.stringValue] = value
        }
    }

    private struct Element<T: Decodable>: Decodable {
        var value: T?
        /// The element as written, when `value` could not be read from it.
        var raw: JSONValue?

        init(from decoder: any Decoder) throws {
            value = try? T(from: decoder)
            raw = value == nil ? try? JSONValue(from: decoder) : nil
        }
    }
}
