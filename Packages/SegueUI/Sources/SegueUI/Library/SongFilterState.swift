import Library

/// What a song list is filtered by: the typed query (free text plus typed tokens such as
/// "ready, upbeat, key G", parsed by `SongFilter.parse`) and the chips toggled beside it.
/// Simple filtering only (phase 2); nothing is saved.
public struct SongFilterState: Equatable, Sendable {
    public var query = ""
    /// Tag chips that are on.
    public var tags: Set<String> = []
    /// Proficiency chips that are on.
    public var proficiencies: Set<Proficiency> = []

    public init(query: String = "", tags: Set<String> = [], proficiencies: Set<Proficiency> = []) {
        self.query = query
        self.tags = tags
        self.proficiencies = proficiencies
    }

    /// The typed tokens and the chips combined. Typed tags and chip tags are compared
    /// case-insensitively, so typing a tag whose chip is on adds nothing.
    public func filter(knownTags: [String]) -> SongFilter {
        var filter = SongFilter.parse(query, knownTags: knownTags)
        LibraryLexicon.apply(to: &filter, knownTags: knownTags)
        let typed = Set(filter.tags.map { $0.lowercased() })
        filter.tags.formUnion(tags.filter { !typed.contains($0.lowercased()) })
        filter.proficiencies.formUnion(proficiencies)
        return filter
    }

    /// Whether anything narrows the list (typed text, typed tokens or chips).
    public var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tags.isEmpty
            || !proficiencies.isEmpty
    }

    /// Whether the tag chip `tag` is on (case-insensitive).
    public func hasTag(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// Turns the tag chip `tag` on or off.
    public mutating func toggleTag(_ tag: String) {
        if hasTag(tag) {
            tags = tags.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        } else {
            tags.insert(tag)
        }
    }

    /// Turns the proficiency chip `level` on or off.
    public mutating func toggle(_ level: Proficiency) {
        if proficiencies.contains(level) {
            proficiencies.remove(level)
        } else {
            proficiencies.insert(level)
        }
    }
}
