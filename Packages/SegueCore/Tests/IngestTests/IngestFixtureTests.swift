import ChordPro
import Foundation
@testable import Ingest
import Testing

/// Golden paste fixtures (`Tests/Fixtures/paste/`): each `<id>.txt` / `<id>.crd` goes through
/// `IngestPipeline` with no provider and must equal `<id>.cho` byte for byte, round trip
/// through the ChordPro parser, lose no chord and change no lyric word.
///
/// `INGEST_RECORD=1 swift test --filter IngestFixtureTests` rewrites the `.cho` files (review
/// every diff by eye: they are the spec).
struct IngestFixtureTests {
    static let fixtures: [String] = PasteFixtures.names

    @Test(arguments: fixtures)
    func `fixture converts to its golden ChordPro`(name: String) throws {
        let result = try PasteFixtures.ingest(name)
        let goldenURL = PasteFixtures.sourceDirectory
            .appendingPathComponent(PasteFixtures.stem(name) + ".cho")
        if ProcessInfo.processInfo.environment["INGEST_RECORD"] == "1" {
            try Data(result.text.utf8).write(to: goldenURL)
        }
        let golden = try #require(String(data: Data(contentsOf: goldenURL), encoding: .utf8))
        #expect(result.text == golden)
    }

    @Test(arguments: fixtures)
    func `result round trips through the ChordPro parser`(name: String) throws {
        let result = try PasteFixtures.ingest(name)
        let (document, diagnostics) = ChordProParser.parse(result.text)
        #expect(diagnostics.isEmpty, "\(diagnostics)")
        #expect(ChordProSerializer.serialize(document) == result.text)
        #expect(document == result.document)
    }

    @Test(arguments: fixtures)
    func `no chord is lost`(name: String) throws {
        let result = try PasteFixtures.ingest(name)
        #expect(PasteFixtures.outputChords(result.document) == PasteFixtures.sourceChords(result))
        for case let .removedLine(text, _) in result.diagnostics {
            #expect(!ChordLines.isChordLine(text) && !ChordLines.hasInlineChords(text), "\(text)")
        }
    }

    @Test(arguments: fixtures)
    func `no lyric word changes`(name: String) throws {
        let result = try PasteFixtures.ingest(name)
        let source = result.lines
            .filter { $0.lineClass == .lyricLine }
            .flatMap { LyricGuard.tokens(ofSourceLine: $0.text) }
        #expect(LyricGuard.tokens(of: result.document) == source)
    }

    @Test
    func `fixture set covers the brief`() throws {
        #expect(Self.fixtures.count >= 30)
        #expect(Self.fixtures.count(where: { $0.hasPrefix("H") }) >= 8)
        #expect(Self.fixtures.count(where: { $0.hasSuffix(".crd") }) >= 2)
        #expect(Self.fixtures.contains("E07-short-unlabelled.txt"))
        #expect(Self.fixtures.contains("H07-bare-hinglish-lyrics.txt"))
        let gold = try PasteFixtures.gold()
        #expect(Set(gold.keys) == Set(Self.fixtures.map(PasteFixtures.stem)))
    }

    /// R101 pins: with a capo, `{key}` is the shapes key (a stated sounding key is lowered by
    /// the capo when the chords fit that better), and tuning and strumming lines become
    /// `{comment}` lines.
    @Test
    func `capo writes the shapes key and unknown lines become comments`() throws {
        let result = try PasteFixtures.ingest("E24-capo-sounding-key.txt")
        #expect(result.text
            .hasPrefix("{title: Cinder Lane}\n{artist: Mabel Orrin}\n{key: G}\n{capo: 2}\n"))
        #expect(result.text.contains("{comment: Tuning: Standard}"))
        #expect(result.text.contains("{comment: Strumming: D D U U D U}"))
        let shapes = try PasteFixtures.ingest("E05-colon-headers-repeats.txt")
        #expect(shapes.text.contains("{key: C}\n{capo: 2}"))
    }

    /// The refinement seam: labels and metadata by index re-render without touching lyrics.
    @Test
    func `reassembling with refined labels keeps every lyric`() throws {
        let result = try PasteFixtures.ingest("E07-short-unlabelled.txt")
        #expect(result.questions.unheadedBlocks == [0, 1])
        var metadata = result.metadata
        metadata.title = "Monday"
        let refined = result.reassembled(labels: [1: .chorus], metadata: metadata)
        #expect(refined.text.hasPrefix("{title: Monday}\n\n{start_of_verse}"))
        #expect(refined.text.contains("{start_of_chorus}\n[D]Oh, Monday"))
        #expect(refined.questions.unheadedBlocks == [0])
        #expect(LyricGuard
            .check(original: result.document, refined: refined.document) == .identical)
    }

    /// Every gold label lines up with a block, and headed blocks are always right.
    @Test
    func `deterministic labels match the gold set`() throws {
        let gold = try PasteFixtures.gold()
        var score = LabelScore()
        for name in Self.fixtures {
            let result = try PasteFixtures.ingest(name)
            let entry = try #require(gold[PasteFixtures.stem(name)])
            #expect(entry.labels.count == result.blocks.count, "\(name): block count")
            guard !result.isAlreadyChordPro else { continue }
            score.add(result, gold: entry)
        }
        print(score.report)
        #expect(score.headedCorrect == score.headed)
        // R101's repetition rule took the gold set from 92% to 99% (P3-2 step 0).
        #expect(score.correct * 100 >= score.total * 98, "\(score.report)")
    }
}

/// Label accuracy of the deterministic result against `gold.json`.
struct LabelScore {
    var total = 0
    var correct = 0
    var headed = 0
    var headedCorrect = 0
    var titles = 0
    var titlesCorrect = 0
    var artists = 0
    var artistsCorrect = 0

    mutating func add(_ result: IngestResult, gold: PasteFixtures.GoldEntry) {
        for (block, accepted) in zip(result.blocks, gold.labels) {
            let label = Self.deterministicLabel(block)
            total += 1
            if accepted.contains(label) {
                correct += 1
            }
            if block.labelSource == .header {
                headed += 1
                headedCorrect += accepted.contains(label) ? 1 : 0
            }
        }
        titles += 1
        titlesCorrect += gold.title.contains(Self.norm(result.metadata.title)) ? 1 : 0
        artists += 1
        artistsCorrect += gold.artist.contains(Self.norm(result.metadata.artists.first)) ? 1 : 0
    }

    var report: String {
        func percent(_ part: Int, _ whole: Int) -> String {
            whole == 0 ? "n/a" : String(format: "%.1f%%", Double(part) * 100 / Double(whole))
        }
        return """
        Deterministic labels: \(correct)/\(total) blocks (\(percent(correct, total))), \
        headed \(headedCorrect)/\(headed) (\(percent(headedCorrect, headed))), \
        unheaded \(correct - headedCorrect)/\(total - headed) \
        (\(percent(correct - headedCorrect, total - headed))). \
        Title \(titlesCorrect)/\(titles), artist \(artistsCorrect)/\(artists).
        """
    }

    /// What the deterministic result renders: the header's (or the R101 repetition rule's)
    /// label, `other` for metadata blocks, `verse` for unlabelled placeholders.
    static func deterministicLabel(_ block: IngestBlock) -> String {
        switch block.role {
        case .metadata, .passthrough: "other"
        case .content: (block.label ?? .verse).rawValue
        }
    }

    static func norm(_ text: String?) -> String? {
        let folded = (text ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        return folded.isEmpty ? nil : folded
    }
}
