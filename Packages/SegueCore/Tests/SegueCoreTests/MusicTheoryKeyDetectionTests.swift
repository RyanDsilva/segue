import Foundation
import MusicTheory
import Testing

/// Key-detection table over the fixture corpus (docs/phases/1-editor-and-music-theory.md,
/// "Pure-logic tests"): every fixture with chords has an expected key or "ambiguous".
/// Fixtures with a `{key}` must detect that key from their chords alone; the expectation
/// table pins the rest. This table is what `KeyDetector.ambiguityMargin` is tuned against.
struct MusicTheoryKeyDetectionTests {
    enum Expected: Sendable, CustomStringConvertible {
        /// No chords: `detect` returns nil.
        case noChords
        case key(String)
        /// Ambiguous, with the winner the scorer must still pick.
        case ambiguous(String)

        var description: String {
            switch self {
            case .noChords: "none"
            case let .key(name): name
            case let .ambiguous(name): "ambiguous (\(name))"
            }
        }
    }

    /// Fixtures without a `{key}` (or with chords the declared key must still be checked
    /// against) and the verdict a musician would give.
    static let undeclared: [String: Expected] = [
        "crlf-line-endings.cho": .key("E"),
        "editing-no-key.cho": .key("C"),
        "empty.cho": .noChords,
        // vi IV I V loop starting and ending on the vi chord: the minor reading wins, the
        // same verdict as the declared `Am F C G` of comments-both-kinds.cho.
        "generic-sections.cho": .key("Em"),
        // This scanner reads `[C[D]` as `D` (the open `[` restarts the group).
        "malformed-brackets.cho": .key("D"),
        "malformed-braces.cho": .key("G"),
        // Just `G C`: I-IV in G or V-I in C.
        "malformed-sections.cho": .ambiguous("G"),
        "metadata-only.cho": .noChords,
        "trailing-whitespace.cho": .key("E"),
        "unknown-directives.cho": .key("D"),
        // `Dm G` vamp: D dorian or C major's ii-V; neither is clearly right. C and Am tie
        // on fit alone and the tie goes to the lower tonic, major first.
        "keydetect-dorian-vamp.cho": .ambiguous("C"),
        "keydetect-harmonic-minor.cho": .key("Em"),
        "keydetect-flat-key.cho": .key("Eb"),
    ]

    static let fixtures: [CorpusFixture] = CorpusFixture.all

    @Test(arguments: fixtures)
    func `detects expected key`(_ fixture: CorpusFixture) throws {
        let expected: Expected = if fixture.chords.isEmpty {
            .noChords
        } else if let declared = fixture.declaredKey {
            try .key(#require(SongKey(parsing: declared)).name)
        } else {
            try #require(
                Self.undeclared[fixture.name],
                "add \(fixture.name) to the key-detection table",
            )
        }
        let detection = KeyDetector.detect(fixture.chords)
        switch expected {
        case .noChords:
            #expect(detection == nil)
        case let .key(name):
            #expect(detection?.key.name == name, "\(fixture.name): \(Self.summary(detection))")
            #expect(detection?.isAmbiguous == false, "\(fixture.name): \(Self.summary(detection))")
        case let .ambiguous(name):
            #expect(detection?.key.name == name, "\(fixture.name): \(Self.summary(detection))")
            #expect(detection?.isAmbiguous == true, "\(fixture.name): \(Self.summary(detection))")
        }
    }

    @Test
    func `ranking covers all keys deterministically`() throws {
        let chords = ["C", "F", "C", "F"].compactMap { ChordToken(parsing: $0).chord }
        let detection = try #require(KeyDetector.detect(chords))
        #expect(detection.ranking.count == 24)
        #expect(Set(detection.ranking.map(\.key.name)).count == 24)
        // An I-IV vamp ties C and F exactly; the tie goes to the lower tonic.
        #expect(detection.isAmbiguous)
        #expect(detection.ranking.prefix(2).map(\.key.name) == ["C", "F"])
        #expect(KeyDetector.detect(chords) == detection)
        #expect(KeyDetector.detect([]) == nil)
    }

    private static func summary(_ detection: KeyDetection?) -> String {
        guard let detection else { return "nil" }
        let top = detection.ranking.prefix(3).map {
            "\($0.key.name)=\(String(format: "%.3f", $0.score))"
        }
        let ranking = top.joined(separator: " ")
        return "\(detection.key.name) ambiguous=\(detection.isAmbiguous) [\(ranking)]"
    }
}

/// A fixture's chords and `{key}`, read with a deliberately simple scanner so this table does
/// not depend on the ChordPro parser: bracket contents on lyric lines, in order.
struct CorpusFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let declaredKey: String?
    /// Every bracketed token on lyric lines, in order.
    let tokens: [String]

    var testDescription: String {
        name
    }

    /// The tokens that parse as chords.
    var chords: [ChartChord] {
        tokens.compactMap { ChordToken(parsing: $0).chord }
    }

    static let all: [Self] = {
        guard let directory = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return files.filter { $0.hasSuffix(".cho") }.sorted().compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Self(name: name, text: text)
        }
    }()

    init(name: String, text: String) {
        self.name = name
        var key: String?
        var tokens: [String] = []
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("{") {
                key = key ?? Self.keyValue(of: line)
            } else if !line.hasPrefix("#") {
                tokens += Self.bracketed(in: line)
            }
        }
        declaredKey = key
        self.tokens = tokens
    }

    /// The value of a `{key: X}` / `{key X}` directive (any case).
    private static func keyValue(of line: String) -> String? {
        let body = line.dropFirst().prefix { $0 != "}" }
        guard body.lowercased().hasPrefix("key") else { return nil }
        let value = body.dropFirst(3).drop { $0 == ":" || $0 == " " }
        return value.isEmpty ? nil : String(value)
    }

    /// Contents of well-formed `[...]` groups (no nested `[`).
    private static func bracketed(in line: String) -> [String] {
        var result: [String] = []
        var current: String?
        for character in line {
            switch character {
            case "[": current = ""
            case "]":
                if let token = current {
                    result.append(token)
                }
                current = nil
            default: current?.append(character)
            }
        }
        return result
    }
}
