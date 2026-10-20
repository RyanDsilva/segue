import Foundation

/// Any JSON value: a recorded output kept as written, decoded into the task's output type only
/// when it is replayed.
public indirect enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
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
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value):
            if value == value.rounded(), abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// `value` as a JSON value (round trip through `JSONEncoder`).
    public init(encoding value: some Encodable) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    /// Decodes this value as `type`.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

/// One recorded real call: the output it gave, or the typed error it threw.
public struct RecordedCall: Sendable, Hashable, Codable {
    public var task: ModelTaskKind
    /// `ModelTask.inputHash`.
    public var input: String
    public var output: JSONValue?
    public var error: ProviderError?

    public init(task: ModelTaskKind, input: String, output: JSONValue?, error: ProviderError?) {
        self.task = task
        self.input = input
        self.output = output
        self.error = error
    }

    public var key: String {
        "\(task.rawValue)-\(input)"
    }

    /// A call that answered.
    public static func answered<T: ModelTask>(_ task: T, _ output: T.Output) throws -> Self {
        try Self(
            task: T.kind,
            input: task.inputHash,
            output: JSONValue(encoding: output),
            error: nil,
        )
    }

    /// A call that threw.
    public static func failed(_ task: some ModelTask, _ error: ProviderError) -> Self {
        Self(task: type(of: task).kind, input: task.inputHash, output: nil, error: error)
    }
}

/// The recordings of one fixture for one provider:
/// `Tests/Fixtures/paste/recorded/<provider>/<fixture>.json`.
public struct RecordingFile: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var provider: ProviderKind
    public var fixture: String
    /// What produced it (`"apple-fm macOS 26.6.2"`), for the reader only.
    public var source: String
    public var calls: [RecordedCall]

    public init(provider: ProviderKind, fixture: String, source: String, calls: [RecordedCall]) {
        schemaVersion = 1
        self.provider = provider
        self.fixture = fixture
        self.source = source
        self.calls = calls
    }

    /// Pretty, sorted JSON with a trailing newline (stable diffs).
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    /// Every `*.json` recording file in `directory`, sorted by name.
    public static func load(directory: URL) throws -> [Self] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        return try names.map { name in
            try JSONDecoder().decode(
                Self.self,
                from: Data(contentsOf: directory.appendingPathComponent(name)),
            )
        }
    }
}
