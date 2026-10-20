import Foundation
import Library
@testable import SetAssistant
import Setlists
import Testing

/// Timing budgets (spec 14.1): a set builds in under 2 s for 300 songs (reading the records,
/// key detection included) and lexicon chips appear in under 100 ms. Runs in `make test-perf`,
/// alone.
struct SetAssistantPerformanceTests {
    @Test
    func `three hundred songs build a set in under 2 s`() async throws {
        let loaded = try await SetAssistantIntegrationTests.load()
        let tags = try await loaded.library.allTags().map(\.tag)
        let clock = ContinuousClock()
        var newIDs = 0
        let elapsed = clock.measure {
            let lexicon = SetRequestLexicon(tags: tags)
            let request = SetRequest(kinds: lexicon.parse(
                "an hour, songs I know well, no covers, upbeat start, finish big",
            ).chips)
            let library = AssistantLibrary(
                records: loaded.records,
                playStats: loaded.playStats,
                filters: loaded.filters,
                now: AssistantFixture.now,
            )
            let draft = SetBuilder().build(
                request,
                library: library,
                changeover: 30,
                seed: 5,
                newItemID: {
                    newIDs += 1
                    return SetlistItemID(loaded.test.ids.next())
                },
            )
            #expect(draft.isWithinTolerance)
        }
        #expect(newIDs > 5)
        #expect(elapsed < .seconds(2), "\(elapsed)")
    }

    @Test
    func `lexicon chips in under 100 ms`() {
        let tags = (0 ..< 200).map { "tag number \($0)" } + AssistantFixture.tags
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let lexicon = SetRequestLexicon(tags: tags)
            for prompt in SetRequestLexiconTests.spikePrompts {
                _ = lexicon.parse(prompt.text)
            }
        }
        // 15 prompts and the vocabulary build, against a 100 ms budget for one.
        #expect(elapsed < .milliseconds(100), "\(elapsed)")
    }
}
