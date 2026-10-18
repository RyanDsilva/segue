import Foundation
import Library
import Services

// Analytics of the library (WS3 spec 5 rows 5, 6, 8, 13 and 17). Only enums, buckets and
// booleans are recorded: never a title, a file name or the search text.

extension LibraryViewModel {
    /// Row 5 plus the song milestones (row 13), after the catalog was reloaded.
    func recordSongsCreated(_ source: SongSource) {
        services.record(.songCreated(source))
        recordSongMilestones()
    }

    /// Row 6 (and row 5 / 13 when songs came in) for one import operation.
    func recordImport(_ summary: ImportSummary, files: Int, method: ImportMethod) {
        let outcome: ImportOutcome = if summary.imported.isEmpty {
            .nothingImported
        } else if summary.skipped.isEmpty {
            .all
        } else {
            .partial
        }
        services.record(.songImported(
            method: method,
            files: SmallBucket(max(files, summary.imported.count + summary.skipped.count)),
            outcome: outcome,
            nonUTF8: !summary.converted.isEmpty,
        ))
        guard !summary.imported.isEmpty else { return }
        services.record(.milestoneReached(.firstImport, daysSinceFirstLaunch: daysSinceFirstLaunch))
        recordSongsCreated(.import)
    }

    /// Rows 8 and 17 once the library's results for `state` are on screen.
    func recordSearch(_ state: SongFilterState, _ found: SearchOutcome) {
        let filter = state.filter(knownTags: tags.map(\.tag))
        if filter.hasConstraints {
            services.record(.featureUsed(.filterChips, .library))
        }
        guard !filter.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchRecorder.cancel()
            return
        }
        services.record(.featureUsed(.search, .library))
        searchRecorder.resultsShown(.library, tier: found.firstTier, count: found.records.count)
    }

    /// The setlist builder's library column: `search(_:)` plus row 17 in the builder
    /// context.
    func builderSearch(_ state: SongFilterState) async throws -> [SongRecord] {
        let found = try await searchWithTier(state)
        if state.filter(knownTags: tags.map(\.tag)).text
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            builderSearchRecorder.cancel()
        } else {
            builderSearchRecorder.resultsShown(
                .builder,
                tier: found.firstTier,
                count: found.records.count,
            )
        }
        return found.records
    }

    private func recordSongMilestones() {
        let days = daysSinceFirstLaunch
        services.record(.milestoneReached(.firstSong, daysSinceFirstLaunch: days))
        if catalog.count >= 10 {
            services.record(.milestoneReached(.tenSongs, daysSinceFirstLaunch: days))
        }
        if catalog.count >= 50 {
            services.record(.milestoneReached(.fiftySongs, daysSinceFirstLaunch: days))
        }
    }
}
