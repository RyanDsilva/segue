import ChordPro
import Foundation
@testable import Ingest
import ModelPort
import Testing

/// The refinement merge (`IngestPipeline.apply`) driven through `PasteRefiner` + `Router` +
/// `ScriptedProvider` replaying real Foundation Models recordings
/// (`Tests/Fixtures/paste/recorded/fm/<fixture>.json`, made by `make eval-ai RECORD=1`). Each
/// refined result must equal `recorded/fm/<fixture>.cho` byte for byte and keep every lyric
/// word and chord of the deterministic result.
///
/// `REFINE_RECORD=1 swift test --filter IngestRefinementTests` rewrites the refined `.cho`
/// files (review every diff by eye).
struct IngestRefinementTests {
    static let recordedDirectory = PasteFixtures.sourceDirectory
        .appendingPathComponent("recorded/fm")

    static let recordedFixtures: [String] = {
        let names = try? FileManager.default.contentsOfDirectory(atPath: recordedDirectory.path)
        return (names ?? []).filter { $0.hasSuffix(".json") }
            .map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    static func fmRouter() throws -> Router {
        let fm = try ScriptedProvider(
            id: .foundationModels,
            directory: recordedDirectory,
            onMissing: { Issue.record("no FM recording for \($0)") },
        )
        return Router(providers: [fm])
    }

    static func fixtureName(_ stem: String) -> String {
        PasteFixtures.names.first { PasteFixtures.stem($0) == stem } ?? "\(stem).txt"
    }

    @Test(arguments: recordedFixtures)
    func `FM recordings refine the fixture to its golden ChordPro`(stem: String) async throws {
        let base = try PasteFixtures.ingest(Self.fixtureName(stem))
        let update = try await PasteRefiner.refined(base, router: Self.fmRouter())
        let refined = update.result
        let goldenURL = Self.recordedDirectory.appendingPathComponent("\(stem).cho")
        if ProcessInfo.processInfo.environment["REFINE_RECORD"] == "1" {
            try Data(refined.text.utf8).write(to: goldenURL)
        }
        let golden = try #require(String(data: Data(contentsOf: goldenURL), encoding: .utf8))
        #expect(refined.text == golden)
        #expect(LyricGuard.check(original: base.document, refined: refined.document) == .identical)
        #expect(PasteFixtures.outputChords(refined.document) == PasteFixtures
            .outputChords(base.document))
        #expect(ChordProParser.parse(refined.text).1.isEmpty)
        for report in update.reports.values where report.answeredBy == nil {
            #expect(report.attempts.last?.outcome != .answered)
        }
    }

    /// R174: artists come from code only. Over every paste fixture, the replayed FM answers
    /// leave the artist list exactly as code found it, and code's list matches `gold.json`
    /// (all 46 recorded pastes were right before the model was taken off artists).
    @Test
    func `artists are code's, with or without the FM recordings`() async throws {
        let gold = try PasteFixtures.gold()
        var total = 0
        var right = 0
        for name in PasteFixtures.names {
            let stem = PasteFixtures.stem(name)
            let base = try PasteFixtures.ingest(name)
            guard !base.isAlreadyChordPro else { continue }
            let refined = Self.recordedFixtures.contains(stem)
                ? try await PasteRefiner.refined(base, router: Self.fmRouter()).result
                : base
            #expect(refined.metadata.artists == base.metadata.artists, "\(name)")
            guard let entry = gold[stem] else { continue }
            total += 1
            right += entry.artist.contains(base.metadata.artists.compactMap(LabelScore.norm))
                ? 1 : 0
        }
        #expect(total > 0 && right == total)
    }

    /// Every fixture that asks a model anything has an FM recording.
    @Test
    func `every fixture with questions has an FM recording`() throws {
        for name in PasteFixtures.names {
            let result = try PasteFixtures.ingest(name)
            let asks = PasteRefiner.labelTask(for: result) != nil
                || PasteRefiner.metadataTask(for: result) != nil
                || PasteRefiner.ambiguousLineTask(for: result) != nil
            #expect(asks == Self.recordedFixtures.contains(PasteFixtures.stem(name)), "\(name)")
        }
    }

    // MARK: - The merge rules

    @Test
    func `labels are taken only for unheaded blocks`() throws {
        let base = try PasteFixtures.ingest("E07-short-unlabelled.txt")
        #expect(base.questions.unheadedBlocks == [0, 1])
        let headed = try PasteFixtures.ingest("E01-ug-headers.txt")
        let refined = IngestPipeline.apply(
            Refinements(labels: [1: .bridge, 2: .bridge]),
            to: headed,
        )
        #expect(refined.text == headed.text)
        let applied = IngestPipeline.apply(Refinements(labels: [1: .chorus]), to: base)
        #expect(applied.blocks[1].label == .chorus && applied.blocks[1].labelSource == .refined)
        #expect(applied.text.contains("{start_of_chorus}"))
    }

    @Test
    func `metadata fills only what code did not find, and a model key is only a suggestion`(
    ) throws {
        let base = try PasteFixtures.ingest("E07-short-unlabelled.txt")
        #expect(base.metadata.title == nil)
        let refined = IngestPipeline.apply(Refinements(title: "Monday"), to: base)
        #expect(refined.text.hasPrefix("{title: Monday}\n"))
        #expect(refined.metadata.artists.isEmpty)
        #expect(refined.refinedFields == [.title])

        let titled = try PasteFixtures.ingest("E01-ug-headers.txt")
        let kept = IngestPipeline.apply(
            Refinements(title: "Other Song"),
            to: titled,
        )
        #expect(kept.metadata.title == titled.metadata.title)
        #expect(kept.refinedFields.isEmpty)

        // A model key never reaches the .cho; it replaces the suggestion only when KeyDetector
        // is ambiguous and the key is one of its top two.
        for name in PasteFixtures.names {
            let result = try PasteFixtures.ingest(name)
            guard result.keyInference.isAmbiguous, let second = result.keyInference.topTwo.last
            else { continue }
            let suggested = IngestPipeline.apply(Refinements(key: second.name), to: result)
            #expect(suggested.keyInference.key == second)
            #expect(suggested.text == result.text)
            let outside = IngestPipeline.apply(Refinements(key: "F#m"), to: result)
            #expect(outside.keyInference.refined == nil || result.keyInference.topTwo.contains {
                $0.name == "F#m"
            })
        }
    }

    /// A refinement that would drop lyric words (a song block relabelled `other` renders as
    /// comments) is rejected for that block and logged; the rest still applies.
    @Test
    func `the lyric guard rejects a refinement that changes lyrics`() throws {
        let base = try PasteFixtures.ingest("E07-short-unlabelled.txt")
        let refined = IngestPipeline.apply(Refinements(labels: [0: .other, 1: .chorus]), to: base)
        #expect(refined.diagnostics.contains(.refinementRejected(block: 0)))
        #expect(!refined.diagnostics.contains(.refinementRejected(block: 1)))
        #expect(refined.blocks[0].labelSource == .placeholder)
        #expect(refined.blocks[1].label == .chorus)
        #expect(LyricGuard.check(original: base.document, refined: refined.document) == .identical)
    }

    /// R124 regression: two adjacent inline-chord blocks labelled `other` each keep their
    /// words alone (inline-chord lines stay lyrics), but together their loose lines run into
    /// one group. Regrouping is not a lyric change, and one label that does fail never
    /// discards the others.
    @Test
    func `adjacent other blocks with inline chords keep every other label`() {
        let paste = """
        G              C
        Harbor lights are burning low

        [G]Lanterns swing along the [C]quay
        [D]Every rope is coiled and [G]free

        [G]Gulls are calling [C]out to sea
        [D]Tide is turning [G]home to me

        C              G
        Shine, shine, harbor lights
        D              G
        Guide them through the night

        G              C
        Sails are down and boats are in
        """
        let base = IngestPipeline.ingest(paste, origin: .paste)
        #expect(base.questions.unheadedBlocks == [0, 1, 2, 3, 4])
        let refined = IngestPipeline.apply(
            Refinements(labels: [1: .other, 2: .other, 3: .chorus, 4: .other]),
            to: base,
        )
        // Block 4 has no inline chords: `other` would turn its lyrics into comments.
        #expect(refined.diagnostics.filter {
            if case .refinementRejected = $0 {
                true
            } else {
                false
            }
        } == [.refinementRejected(block: 4)])
        #expect(refined.blocks[1].label == .other && refined.blocks[2].label == .other)
        #expect(refined.blocks[3].label == .chorus)
        #expect(refined.blocks[4].labelSource == .placeholder)
        #expect(LyricGuard.check(original: base.document, refined: refined.document) == .identical)
    }

    @Test
    func `model titles that are chords, capo or tuning notes are dropped`() {
        let task = MetadataTask(
            topLines: ["Capo 2", "E-A-D-G-B-e", "G D Em C", "Harbor Song by Ada Lund"],
            bottomLines: [],
            chords: ["G", "D", "Em", "C"],
        )
        for title in ["G D Em C", "Capo 2", "E-A-D-G-B-e"] {
            let answer = PasteRefiner.refinements(
                MetadataOutput(title: title, key: ""),
                for: task,
            )
            #expect(answer.title == nil, "\(title)")
        }
        let invented = PasteRefiner.refinements(
            MetadataOutput(title: "Something Else", key: "G"),
            for: task,
        )
        #expect(invented.title == nil && invented.key == "G")
    }

    /// R163: the sheet's own spelling of the matched title, never the model's casing; a
    /// value not in the sheet is dropped; no AI step re-spells a romanized name.
    @Test
    func `a model title keeps the sheet's spelling`() {
        let task = MetadataTask(
            topLines: ["Tum Hi Ho", "Singer - Arijit Singh & mithoon"],
            bottomLines: [],
            chords: ["G", "D"],
        )
        let answer = PasteRefiner.refinements(
            MetadataOutput(title: "TUM HI HO", key: ""),
            for: task,
        )
        #expect(answer.title == "Tum Hi Ho")
        let corrected = PasteRefiner.refinements(
            MetadataOutput(title: "Tum Hi Hoo", key: ""),
            for: task,
        )
        #expect(corrected.title == nil)
    }

    /// R121, R174: the converter wins on the title, and artists come from code only. No
    /// metadata call when code found a title; the refined result's artists are always code's.
    @Test
    func `the converter wins on the title and owns the artists`() throws {
        var untitled = 0
        for name in PasteFixtures.names {
            let result = try PasteFixtures.ingest(name)
            guard !result.isAlreadyChordPro else { continue }
            if result.metadata.title != nil {
                #expect(PasteRefiner.metadataTask(for: result) == nil, "\(name)")
                continue
            }
            untitled += 1
            let refined = IngestPipeline.apply(Refinements(title: "Made Up"), to: result)
            #expect(refined.metadata.artists == result.metadata.artists, "\(name)")
            #expect(refined.refinedFields.isSubset(of: [.title]), "\(name)")
        }
        #expect(untitled > 0)
    }

    /// Spike 5.3 / the real-paste eval: no metadata call without a top or bottom candidate.
    @Test
    func `no metadata call without top or bottom candidate lines`() throws {
        let base = try PasteFixtures.ingest("E07-short-unlabelled.txt")
        #expect(base.questions.metadataCandidates.map {
            $0.topLines.isEmpty && $0.bottomLines.isEmpty
        } ?? true)
        #expect(PasteRefiner.metadataTask(for: base) == nil)
    }

    @Test
    func `AI off leaves the deterministic result`() async throws {
        let base = try PasteFixtures.ingest("E07-short-unlabelled.txt")
        let fm = ScriptedProvider(id: .foundationModels, onMissing: { Issue.record("\($0)") })
        let update = await PasteRefiner.refined(
            base,
            router: Router(providers: [fm], isEnabled: { false }),
        )
        #expect(update.result.text == base.text)
        #expect(update.reports.values.allSatisfy { $0.skipped == .aiOff })
        #expect(fm.calls.isEmpty)
    }

    // MARK: - Budget and chunks

    /// The FM context budget (4,096 tokens before macOS 27, chars/3 estimate): the 40-block
    /// fixture fits one call (spike 2.3: about 35+ blocks fit); with a smaller window (here
    /// 2,048, like the spike's forced-budget variant F) it chunks on block boundaries, every
    /// block once, in order, each chunk within budget.
    @Test
    func `a 40-block sheet fits the window and chunks when the window is smaller`() async throws {
        let result = try PasteFixtures.ingest("E20-forty-blocks.txt")
        let task = SectionLabelTask(blocks: result.blocks.map {
            .init(index: $0.index, lines: $0.lines.map(\.text), hint: $0.hints.summary)
        })
        #expect(task.blocks.count >= 40)
        func plan(contextSize: Int) async -> (ranges: [Range<Int>], budget: Int) {
            let budget = LabelChunking.budget(
                contextSize: contextSize,
                instructionTokens: LabelChunking.estimatedTokens(ModelPrompts.labelInstructions),
                schemaTokens: 204,
                responseTokens: ModelPrompts.labelResponseTokens(blocks: task.blocks.count),
            )
            let ranges = await LabelChunking.plan(blockCount: task.blocks.count, budget: budget) {
                LabelChunking.estimatedTokens(ModelPrompts.labelPrompt(task, range: $0))
            }
            return (ranges, budget)
        }
        let full = await plan(contextSize: 4096)
        #expect(full.ranges == [0 ..< task.blocks.count])
        let small = await plan(contextSize: 2048)
        #expect(small.ranges.count > 1)
        #expect(small.ranges.flatMap(\.self) == Array(0 ..< task.blocks.count))
        for range in small.ranges {
            let prompt = ModelPrompts.labelPrompt(task, range: range)
            #expect(LabelChunking.estimatedTokens(prompt) <= small.budget || range.count == 1)
            #expect(prompt.contains("Label only these blocks"))
        }
    }
}
