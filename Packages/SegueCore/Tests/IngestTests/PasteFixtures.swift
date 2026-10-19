import ChordPro
import Foundation
@testable import Ingest
import Testing

/// Loading and bookkeeping for the paste fixtures.
enum PasteFixtures {
    /// `<id>.txt` and `<id>.crd` names, sorted.
    static let names: [String] = {
        guard let directory = Bundle.module.url(
            forResource: "paste", withExtension: nil, subdirectory: "Fixtures",
        ),
            let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return files.filter { $0.hasSuffix(".txt") || $0.hasSuffix(".crd") }.sorted()
    }()

    /// The fixture folder in the source tree (record mode writes goldens here).
    static let sourceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/paste")

    static func stem(_ name: String) -> String {
        (name as NSString).deletingPathExtension
    }

    /// Reads a fixture like import does: UTF-8, else Windows Latin 1.
    static func text(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: nil, subdirectory: "Fixtures/paste",
        ))
        let data = try Data(contentsOf: url)
        return try #require(String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252))
    }

    static func ingest(_ name: String) throws -> IngestResult {
        let origin: IngestOrigin = name.hasSuffix(".crd") ? .file(extension: "crd") : .paste
        return try IngestPipeline.ingest(text(name), origin: origin)
    }

    /// Chord tokens of the source in order: chord lines (bar lines and repeat marks
    /// excluded), header-line chords and inline `[chords]`.
    static func sourceChords(_ result: IngestResult) -> [String] {
        var chords: [String] = []
        for line in result.lines {
            switch line.lineClass {
            case .chordLine:
                chords += chordLineTokens(line.text)
            case .headerLine:
                if let trailing = HeaderParser.parse(line.text)?.trailingChords {
                    chords += chordLineTokens(trailing)
                }
            case .lyricLine, .metadata, .unknown:
                chords += ChordLines.inlineChords(line.text)
            default:
                continue
            }
        }
        return chords
    }

    private static func chordLineTokens(_ text: String) -> [String] {
        ChordLines.tokens(text).map(\.text).filter { token in
            switch ChordLines.kind(of: token) {
            case .chord, .unknown: true
            case .decoration, .repeatMark: false
            }
        }
    }

    /// Chord tokens of the converted document in order.
    static func outputChords(_ document: SongDocument) -> [String] {
        func chords(_ blocks: [Block]) -> [String] {
            blocks.flatMap { block -> [String] in
                switch block {
                case let .line(line): line.segments.compactMap(\.chord)
                case let .section(section): chords(section.items)
                default: []
                }
            }
        }
        return chords(document.blocks)
    }

    // MARK: - Gold

    /// One fixture's gold (same shape as the spike's `gold.py`): each label entry lists the
    /// acceptable labels; `title`/`artist` list acceptable normalized values (`nil` = none).
    struct GoldEntry {
        var labels: [[String]]
        var title: [String?]
        var artist: [String?]
        var key: [String]
        var keyStated: Bool
    }

    static func gold() throws -> [String: GoldEntry] {
        let url = try #require(Bundle.module.url(
            forResource: "gold", withExtension: "json", subdirectory: "Fixtures/paste",
        ))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let entries = try #require(object as? [String: [String: Any]])
        return entries.mapValues { entry in
            GoldEntry(
                labels: (entry["labels"] as? [Any] ?? []).map(alternatives),
                title: optionalAlternatives(entry["title"]),
                artist: optionalAlternatives(entry["artist"]),
                key: alternatives(entry["key"] ?? "unknown"),
                keyStated: entry["keyStated"] as? Bool ?? false,
            )
        }
    }

    private static func alternatives(_ value: Any) -> [String] {
        (value as? [String]) ?? [(value as? String) ?? ""]
    }

    private static func optionalAlternatives(_ value: Any?) -> [String?] {
        switch value {
        case let list as [Any]: list.map { LabelScore.norm($0 as? String) }
        case let text as String: [LabelScore.norm(text)]
        default: [nil]
        }
    }
}
