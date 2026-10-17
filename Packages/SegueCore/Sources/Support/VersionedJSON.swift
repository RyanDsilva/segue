import Foundation

/// The one JSON dialect Segue writes (sidecars, setlists): pretty-printed, sorted keys,
/// ISO 8601 dates with milliseconds, trailing newline. Deterministic bytes for equal values.
public enum SegueJSON {
    /// Encodes `value` in the canonical on-disk form.
    public static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(fractionalDateStyle))
        }
        var data = try encoder.encode(value)
        data.append(contentsOf: Array("\n".utf8))
        return data
    }

    /// Decodes `type` from `data`. Dates may be written with or without milliseconds.
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: fractionalDateStyle) {
                return date
            }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(string)",
            )
        }
        return try decoder.decode(type, from: data)
    }

    /// `date` rounded to whole milliseconds, the precision the on-disk form keeps. Stamp
    /// timestamps through this so a value survives a save/reload round trip unchanged.
    public static func stamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    private static let fractionalDateStyle = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
    )
}

/// Errors from `SchemaMigrator`.
public enum SchemaMigrationError: Error, Equatable, CustomStringConvertible {
    /// The file is not a JSON object.
    case notAnObject
    /// `schemaVersion` is present but not a non-negative integer.
    case invalidSchemaVersion
    /// No migration step is registered from this version.
    case missingStep(from: Int)

    public var description: String {
        switch self {
        case .notAnObject:
            "not a JSON object"
        case .invalidSchemaVersion:
            "schemaVersion is not a non-negative integer"
        case let .missingStep(version):
            "no migration from schemaVersion \(version)"
        }
    }
}

/// Forward migrations for an integer-`schemaVersion` JSON file.
///
/// A file without `schemaVersion` is version 0 (pre-versioned). Each step rewrites the raw
/// JSON object from version `n` to `n + 1`; the migrator then stamps `schemaVersion`.
/// Migration happens in memory only: callers write the migrated value back on next save.
public struct SchemaMigrator: Sendable {
    /// One step: rewrites a version-`n` object into the version-`n + 1` shape.
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void

    /// Result of inspecting a file.
    public enum Outcome: Equatable {
        /// Already at the current version; decode `data` as is.
        case current(Data)
        /// Migrated from an older version; decode `data` (the migrated JSON).
        case migrated(Data, from: Int)
        /// Written by a newer app: open read-only, never rewrite.
        case newer(found: Int)
    }

    public let currentVersion: Int
    private let steps: [Int: Step]

    /// `steps[n]` migrates version `n` to `n + 1`, for every `n < currentVersion`.
    public init(currentVersion: Int, steps: [Int: Step]) {
        self.currentVersion = currentVersion
        self.steps = steps
    }

    public func migrate(_ data: Data) throws -> Outcome {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchemaMigrationError.notAnObject
        }
        let found = try Self.version(of: object)
        if found == currentVersion {
            return .current(data)
        }
        if found > currentVersion {
            return .newer(found: found)
        }
        for version in found ..< currentVersion {
            guard let step = steps[version] else {
                throw SchemaMigrationError.missingStep(from: version)
            }
            try step(&object)
        }
        object["schemaVersion"] = currentVersion
        let migrated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return .migrated(migrated, from: found)
    }

    private static func version(of object: [String: Any]) throws -> Int {
        guard let raw = object["schemaVersion"] else { return 0 }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFNumberGetTypeID(),
              let version = Int(exactly: number.doubleValue),
              version >= 0
        else {
            throw SchemaMigrationError.invalidSchemaVersion
        }
        return version
    }
}
