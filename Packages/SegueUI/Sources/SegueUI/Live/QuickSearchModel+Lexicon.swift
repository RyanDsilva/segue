#if os(macOS)
    import Library
    import SetAssistant
    import SwiftUI

    extension QuickSearchModel {
        /// The stage's NL pick (R65, P3-7): the lexicon reads tags, keys, proficiency, BPM,
        /// artists and movies out of the query ("upbeat in G", "ballads under 90 bpm", "by
        /// arijit", "from kalank", P8-8 section 3.5.2) and the rest goes to the
        /// text search; no model is loaded on stage. A query the lexicon reads nothing from
        /// is a plain text search, as before; the plain search's hits always follow the
        /// lexicon's. Returns the results and the chip titles.
        nonisolated static func lexiconSearch(
            _ text: String,
            in library: LibraryStore,
        ) async throws -> (SearchOutcome, [String]) {
            let tags = try await library.allTags().map(\.tag)
            let songs = try await library.allSongs()
            let parsed = SetRequestLexicon(
                tags: tags,
                artists: LibraryViewModel
                    .mostSongsFirst(songs.flatMap(\.document.metadata.artists)),
                albums: LibraryViewModel
                    .mostSongsFirst(songs.compactMap(\.document.metadata.album)),
            ).parse(text)
            let request = SetRequest(kinds: parsed.chips)
            guard let filter = request.songFilter else {
                return try await (library.searchWithTier(query: text), [])
            }
            let chips = parsed.chips
                .filter { SetRequest(kinds: [$0]).songFilter != nil }
                .map { $0.title() }
            let rest = parsed.searchText
            let found = rest.isEmpty
                ? SearchOutcome(records: songs, firstTier: nil)
                : try await library.searchWithTier(query: rest)
            // The plain text search's hits follow, so a title that happens to name a tag
            // ("Rock") is still found.
            let plain = try await library.searchWithTier(query: text)
            var records = found.records.filter(filter.matches)
            var seen = Set(records.map(\.id))
            records += plain.records.filter { seen.insert($0.id).inserted }
            return (
                SearchOutcome(records: records, firstTier: found.firstTier ?? plain.firstTier),
                chips,
            )
        }
    }

    /// The conditions the stage search read from the query, under the field.
    struct QuickSearchLexiconChips: View {
        let chips: [String]

        var body: some View {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Theme.color.ink.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Theme.color.controlBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Filtering by " + chips.joined(separator: ", "))
            .accessibilityIdentifier(AccessibilityID.liveSearchChips)
        }
    }
#endif
