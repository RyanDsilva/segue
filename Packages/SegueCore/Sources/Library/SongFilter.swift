// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D.
//
// Simple filtering only (phase 2 scope): tags, proficiency, key. Smart and saved filters are
// phase 3.

import Foundation

/// A library filter, combined with the free-text search (`LibraryStore.search`): a song shows
/// when it matches the text search AND `matches(_:)`.
public struct SongFilter: Sendable, Equatable {
    /// Free text left after recognised filter tokens are removed; goes to
    /// `LibraryStore.search(query:)`.
    public var text: String
    /// Every tag must be present (case-insensitive).
    public var tags: Set<String>
    /// Any of these levels; empty = no constraint. Songs without a proficiency never match a
    /// non-empty set.
    public var proficiencies: Set<Proficiency>
    /// The key as written (`{key}` or the detected key), compared by name ("G", "Am");
    /// nil = any.
    public var key: String?

    public init(
        text: String = "",
        tags: Set<String> = [],
        proficiencies: Set<Proficiency> = [],
        key: String? = nil,
    ) {
        self.text = text
        self.tags = tags
        self.proficiencies = proficiencies
        self.key = key
    }

    /// True when no constraint is set (the text may still be non-empty).
    public var hasConstraints: Bool {
        !tags.isEmpty || !proficiencies.isEmpty || key != nil
    }

    /// Whether `song` satisfies the tag, proficiency and key constraints (not `text`).
    public func matches(_ song: SongRecord) -> Bool {
        fatalError("unimplemented: unit D (SongFilter.matches)")
    }

    /// Splits a typed query into filter tokens and free text, as in the builder's search
    /// field ("ready, upbeat, key G"): comma- or space-separated tokens that name a
    /// proficiency level (`learning`, `ready`, `pro`), a known tag (case-insensitive, also
    /// `#tag`) or `key <name>` become constraints; everything else stays in `text`.
    public static func parse(_ query: String, knownTags: [String]) -> Self {
        fatalError("unimplemented: unit D (SongFilter.parse)")
    }
}
