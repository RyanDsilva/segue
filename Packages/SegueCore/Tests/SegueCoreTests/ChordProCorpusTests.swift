import ChordPro
import Foundation
import Testing

/// Parser corpus: one parameterized test over `Tests/Fixtures/*.cho` (the only parser-level
/// test, per docs/phases/0-walking-skeleton.md). Files named `malformed-*` must produce
/// diagnostics; every other fixture must parse cleanly and round trip byte-for-byte.
struct ChordProCorpusTests {
    static let fixtureNames: [String] = {
        guard let directory = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return files.filter { $0.hasSuffix(".cho") }.sorted()
    }()

    /// Spot checks of the derived read-only helpers on a few fixtures.
    static let expectations: [String: Expectation] = [
        "basic-verse-chorus.cho": Expectation(
            metadata: Metadata(
                title: "Lanterns on the Water",
                artists: ["The Quiet Harbour"],
                key: "G",
                capo: 2,
                tempo: 92,
                time: "4/4",
                duration: 225,
            ),
            sectionLabels: ["Verse 1", nil, "Verse 2", "Chorus", nil, "Final Chorus"],
            lyricLine: "Lanterns on the water, drifting out to the bay",
        ),
        "hindi-dil-kabhie.cho": Expectation(
            metadata: Metadata(
                title: "Dil Kabhie Na Bhoole",
                subtitle: "ek purani yaad",
                artists: ["Fixture Sangeet"],
                key: "D",
            ),
            sectionLabels: [nil, "Mukhda", nil, "Mukhda"],
            lyricLine: "Kabhie hansi, kabhie aansu, dil ne sab sambhaal ke rakhe",
        ),
        "hindi-pyaar-ki-raah.cho": Expectation(
            metadata: Metadata(
                title: "Pyaar Ki Raah",
                artists: ["Fixture Sangeet"],
                key: "Am",
                tempo: 84,
            ),
            sectionLabels: ["Verse 1", nil, "Verse 2", "Chorus"],
            lyricLine: "Pyaar ki raah mein, hum tum saath hain",
        ),
        "unknown-directives.cho": Expectation(
            metadata: Metadata(
                title: "Paper Planes Over Pune",
                extra: [
                    "album": ["Monsoon Tapes"], "composer": ["R. Fernandes"],
                    "copyright": ["2024 Original fixture text"], "lyricist": ["R. Fernandes"],
                    "mood": ["bright"], "tuning": ["DADGAD"], "year": ["2024"],
                ],
            ),
            sectionLabels: [nil],
            lyricLine: "Paper planes over Pune, flying through the haze",
        ),
    ]

    struct Expectation {
        var metadata: Metadata
        var sectionLabels: [String?]
        var lyricLine: String
    }

    @Test
    func `corpus has fixtures`() {
        #expect(Self.fixtureNames.count >= 15)
    }

    @Test(arguments: fixtureNames)
    func `fixture round trips`(name: String) throws {
        let source = try Self.load(name)
        let (document, diagnostics) = ChordProParser.parse(source)
        let serialized = ChordProSerializer.serialize(document)

        if name.hasPrefix("malformed-") {
            #expect(!diagnostics.isEmpty, "malformed fixture produced no diagnostics")
        } else {
            #expect(diagnostics.isEmpty, "unexpected diagnostics: \(diagnostics)")
            #expect(
                Array(serialized.utf8) == Array(source.utf8),
                "round trip is not byte-identical",
            )

            // Canonical spelling path: rebuilt without trivia, the document still means the same.
            let canonical = ChordProSerializer
                .serialize(SongDocument(blocks: document.blocks.map(Self.strip)))
            let (reparsed, canonicalDiagnostics) = ChordProParser.parse(canonical)
            #expect(canonicalDiagnostics.isEmpty)
            #expect(
                reparsed == document,
                "canonical serialization changed the meaning:\n\(canonical)",
            )
        }

        // Idempotence for every input.
        let (again, _) = ChordProParser.parse(serialized)
        #expect(Array(ChordProSerializer.serialize(again).utf8) == Array(serialized.utf8))

        if let expected = Self.expectations[name] {
            #expect(document.metadata == expected.metadata)
            #expect(document.displaySections.map(\.label) == expected.sectionLabels)
            #expect(document.plainLyrics.components(separatedBy: "\n").contains(expected.lyricLine))
            #expect(!document.plainLyrics.contains("["))
        }
    }

    @Test
    func `a 300-line song parses in under 5 ms`() throws {
        let verse = try Self.load("hindi-pyaar-ki-raah.cho")
        var source = ""
        var lineCount = 0
        while lineCount < 300 {
            source += verse
            lineCount += verse.split(separator: "\n", omittingEmptySubsequences: false).count - 1
        }
        let clock = ContinuousClock()
        var best = Duration.seconds(1)
        for _ in 0 ..< 5 {
            let elapsed = clock.measure { _ = ChordProParser.parse(source) }
            best = min(best, elapsed)
        }
        #expect(best < .milliseconds(5), "best of 5: \(best)")
    }

    private static func load(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(
            forResource: "Fixtures/\(name)",
            withExtension: nil,
        ))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Rebuilds a block through the public initialisers, dropping all source trivia.
    private static func strip(_ block: Block) -> Block {
        switch block {
        case .blank:
            .blank(BlankLine())
        case let .chorusRef(ref):
            .chorusRef(ChorusRef(label: ref.label))
        case let .commentDirective(comment):
            .commentDirective(CommentDirective(style: comment.style, text: comment.text))
        case let .directive(directive):
            .directive(Directive(name: directive.name, value: directive.value))
        case let .fileComment(comment):
            .fileComment(FileComment(text: comment.text))
        case let .line(line):
            .line(Line(segments: line.segments))
        case let .section(section):
            .section(Section(
                kind: section.kind,
                label: section.label,
                items: section.items.map(strip),
            ))
        }
    }
}
