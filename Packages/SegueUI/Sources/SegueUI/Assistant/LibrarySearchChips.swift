#if os(macOS)
    import Library
    import ModelPort
    import Observation
    import SetAssistant
    import SwiftUI

    /// NL picks in the library search (P3-7, spec 7): the set assistant's lexicon reads the
    /// words `SongFilter.parse` left ("songs I know well under 100 bpm", "kuch romantic
    /// gaane", "no covers in G") into filter conditions; the rest stays the text search.
    enum LibraryLexicon {
        /// The lexicon's reading of `filter.text`, or nil when it reads no song condition.
        static func read(_ text: String, knownTags: [String]) -> LexiconResult? {
            guard !text.allSatisfy(\.isWhitespace) else { return nil }
            let parsed = SetRequestLexicon(tags: knownTags).parse(text)
            return SetRequest(kinds: parsed.chips).songFilter == nil ? nil : parsed
        }

        /// Merges the lexicon's conditions into `filter` and narrows its text to the words the
        /// lexicon did not read.
        static func apply(to filter: inout SongFilter, knownTags: [String]) {
            guard let parsed = read(filter.text, knownTags: knownTags),
                  let read = SetRequest(kinds: parsed.chips).songFilter
            else { return }
            filter.anyTags.formUnion(read.anyTags)
            filter.excludedTags.formUnion(read.excludedTags)
            filter.keys.formUnion(read.keys)
            if !read.proficiencies.isEmpty {
                filter.proficiencies = filter.proficiencies.isEmpty ? read.proficiencies
                    : filter.proficiencies.intersection(read.proficiencies)
            }
            filter.tempo = read.tempo ?? filter.tempo
            filter.text = parsed.searchText
        }

        /// The chips to show for `text`: the conditions the search applies.
        static func chips(_ text: String, knownTags: [String]) -> [SetChip] {
            let rest = SongFilter.parse(text, knownTags: knownTags).text
            guard let parsed = read(rest, knownTags: knownTags) else { return [] }
            return parsed.chips.filter { SetRequest(kinds: [$0]).songFilter != nil }
        }
    }

    /// The library's local-model pass (R65, R116): when the lexicon read the query as a
    /// request, the words neither parser read go to the local model after 0.8 s idle; its tag and
    /// proficiency answers show as dashed chips
    /// that turn into the library's own filter chips when clicked.
    @MainActor
    @Observable
    final class LibrarySuggestions {
        private(set) var chips: [RequestChip] = []

        func refresh(query: String, tags: [String], router: Router) async {
            chips = []
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let rest = SongFilter.parse(query, knownTags: tags).text
            let parsed = SetRequestLexicon(tags: tags).parse(rest)
            // Only a query the lexicon reads as a request goes to the model: a plain title
            // search never loads one (R94 loads per request).
            guard SetRequest(kinds: parsed.chips).songFilter != nil,
                  let task = SuggestedChips.task(for: parsed, libraryTags: tags)
            else { return }
            let routed = await router.run(task)
            guard !Task.isCancelled, let output = routed.output else { return }
            chips = SuggestedChips.suggestions(
                from: output,
                words: task.words,
                libraryTags: tags,
                existing: parsed.chips.map { RequestChip($0, origin: .lexicon) },
            ).filter { chip in
                switch chip.kind {
                case .proficiency, .tag: true
                default: false
                }
            }
        }

        func dismiss(_ chip: RequestChip) {
            chips.removeAll { $0.id == chip.id }
        }
    }

    /// Under the library search: what the lexicon read (instant) and the local model's
    /// dashed suggestions (async). Hidden while there is nothing to show.
    struct LibrarySearchChips: View {
        let model: LibraryViewModel
        @State private var suggestions = LibrarySuggestions()

        var body: some View {
            let tags = model.tags.map(\.tag)
            let read = LibraryLexicon.chips(model.query, knownTags: tags)
            Group {
                if !read.isEmpty || !suggestions.chips.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        if !read.isEmpty {
                            Text("Reading")
                                .font(SchibstedGrotesk.semiBold.font(size: 12))
                                .foregroundStyle(Theme.color.muted)
                        }
                        ForEach(read, id: \.slot) { chip in
                            Text(chip.title())
                                .font(SchibstedGrotesk.semiBold.font(size: 12))
                                .foregroundStyle(Theme.color.ink)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Capsule().fill(Theme.color.ink.opacity(0.08)))
                                .accessibilityIdentifier(AccessibilityID.librarySearchChip)
                        }
                        ForEach(suggestions.chips) { chip in
                            RequestChipView(
                                chip: chip,
                                title: chip.kind.title(),
                                onAccept: { accept(chip) },
                                onRemove: { suggestions.dismiss(chip) },
                            )
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(AccessibilityID.librarySearchChips)
                }
            }
            .task(id: model.query) {
                await suggestions.refresh(query: model.query, tags: tags, router: model.aiRouter)
            }
        }

        /// A suggestion becomes the library's own chip: a tag chip, or Ready and Pro.
        private func accept(_ chip: RequestChip) {
            suggestions.dismiss(chip)
            switch chip.kind {
            case let .tag(tag) where !model.filterState.hasTag(tag):
                model.filterState.toggleTag(tag)
            case .proficiency(.ready):
                model.filterState.proficiencies.formUnion([.ready, .pro])
            case .proficiency(.pro):
                model.filterState.proficiencies.insert(.pro)
            default:
                break
            }
        }
    }
#endif
