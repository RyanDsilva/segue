import Foundation
import Ingest

/// One paste to evaluate: a committed golden fixture or one of Ryan's local pastes.
public struct EvalFixture: Sendable, Hashable {
    /// The file name without extension (`E01-ug-headers`), the gold and recording key.
    public var name: String
    public var text: String
    public var origin: IngestOrigin

    public init(name: String, text: String, origin: IngestOrigin) {
        self.name = name
        self.text = text
        self.origin = origin
    }

    /// Every `.txt` and `.crd` file in `directory`, sorted, read like import does (UTF-8,
    /// else Windows Latin 1).
    public static func load(directory: URL) throws -> [Self] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".txt") || $0.hasSuffix(".crd") }
            .sorted()
        return names.compactMap { name in
            guard let data = try? Data(contentsOf: directory.appending(path: name)),
                  let text = String(data: data, encoding: .utf8)
                  ?? String(data: data, encoding: .windowsCP1252)
            else { return nil }
            let origin: IngestOrigin = name.hasSuffix(".crd") ? .file(extension: "crd") : .paste
            return Self(name: (name as NSString).deletingPathExtension, text: text, origin: origin)
        }
    }
}

/// The accepted answers for one paste (`gold.json`, or the local `gold.local.json`): each
/// block's label or labels (an ambiguous block accepts two), title and artist (nil = none
/// written), and the key or keys.
public struct GoldEntry: Sendable, Hashable {
    public var labels: [[String]]
    /// Normalised (`EvalScore.norm`); `[nil]` means the paste names none.
    public var title: [String?]
    public var artist: [String?]
    public var key: [String]

    public init(labels: [[String]], title: [String?], artist: [String?], key: [String]) {
        self.labels = labels
        self.title = title
        self.artist = artist
        self.key = key
    }

    /// Reads a gold file: `{ "<name>": { "labels": [...], "title": ..., "artist": ...,
    /// "key": ... } }`, where any value may be a list of accepted alternatives.
    public static func load(_ url: URL) throws -> [String: Self] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let entries = object as? [String: [String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return entries.mapValues { entry in
            Self(
                labels: (entry["labels"] as? [Any] ?? []).map(alternatives),
                title: optionalAlternatives(entry["title"]),
                artist: optionalAlternatives(entry["artist"]),
                key: alternatives(entry["key"] ?? "unknown"),
            )
        }
    }

    private static func alternatives(_ value: Any) -> [String] {
        (value as? [String]) ?? [(value as? String) ?? ""]
    }

    private static func optionalAlternatives(_ value: Any?) -> [String?] {
        switch value {
        case let list as [Any]: list.map { EvalScore.norm($0 as? String) }
        case let text as String: [EvalScore.norm(text)]
        default: [nil]
        }
    }
}
