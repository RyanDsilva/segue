import Foundation
import Services
import Testing

/// Rows 33-35 (P9-4 spec 12) ship in both binaries, so no raw value may name a site or a
/// service (R179: techniques, not sites).
struct ServicesImportVocabularyTests {
    static let siteWords = ["ultimate", "guitar", "echords", "e-chords", "chordie", "lrclib"]

    @Test
    func `the import rows name techniques, never sites`() {
        for event in VocabularySample.importEvents {
            let signal = event.render()
            #expect(signal.name.hasPrefix("Segue.Import."))
            for value in signal.params.values {
                let lowered = value.lowercased()
                #expect(!Self.siteWords.contains { lowered.contains($0) }, "\(value)")
            }
        }
        #expect(PasteSource.webPage.rawValue == "webPage")
        #expect(SongSource.web.rawValue == "web")
    }

    @Test
    func `a pick is daily per group and rank`() {
        let picked = AnalyticsEvent.importSearchPicked(SearchPickedSummary(
            group: .tabJSON,
            rank: .one,
            versionRank: .zero,
            previews: .one,
            fromVariant: false,
            romanized: false,
            inLibrary: true,
        ))
        #expect(picked.throttle == .daily(key: "Segue.Import.searchPicked|tabJSON|1"))
        #expect(picked.render().params["segue.inLibrary"] == "true")
    }
}

extension VocabularySample {
    /// Rows 33-35 (P9-4 spec 12): every value of every closed enum at least once.
    static var importEvents: [AnalyticsEvent] {
        let readers = ImportReader.allCases, outcomes = WebImportOutcome.allCases
        let entries = WebImportEntryPoint.allCases, paths = ImportLoadPath.allCases
        let challenges = ImportChallenge.allCases, latencies = LatencyBucket.allCases
        let searchOutcomes = SongSearchOutcome.allCases, groups = ImportSearchGroup.allCases
        let buckets = SmallBucket.allCases
        let rows = [
            readers.count, outcomes.count, entries.count, paths.count, challenges.count,
            latencies.count, searchOutcomes.count, groups.count, buckets.count,
        ].max() ?? 0
        return (0 ..< rows).flatMap { row -> [AnalyticsEvent] in
            [
                .importPageRead(PageReadSummary(
                    reader: pick(readers, row),
                    fellBack: row.isMultiple(of: 2),
                    contentSearch: row.isMultiple(of: 3),
                    outcome: pick(outcomes, row),
                    latency: pick(latencies, row),
                    entry: pick(entries, row),
                    loadPath: pick(paths, row),
                    webKitBlocked: row.isMultiple(of: 4),
                    challenge: pick(challenges, row),
                    openedHere: !row.isMultiple(of: 2),
                    warmUp: row.isMultiple(of: 5),
                )),
                .importSearched(SongSearchedSummary(
                    results: pick(buckets, row),
                    groupsWithResults: pick(buckets, row + 1),
                    groupsFailed: pick(buckets, row + 2),
                    lyricsRetries: pick(buckets, row + 3),
                    variants: pick(buckets, row + 4),
                    outcome: pick(searchOutcomes, row),
                    romanHindiQuery: row.isMultiple(of: 2),
                    latency: pick(latencies, row),
                )),
                .importSearchPicked(SearchPickedSummary(
                    group: pick(groups, row),
                    rank: pick(buckets, row),
                    versionRank: pick(buckets, row + 1),
                    previews: pick(buckets, row + 2),
                    fromVariant: row.isMultiple(of: 2),
                    romanized: row.isMultiple(of: 3),
                    inLibrary: !row.isMultiple(of: 2),
                )),
            ]
        }
    }

    private static func pick<T>(_ values: [T], _ row: Int) -> T {
        values[row % values.count]
    }
}
