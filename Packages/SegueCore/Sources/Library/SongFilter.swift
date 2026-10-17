// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D.
//
// Simple filtering only (phase 2 scope): tags, proficiency, key. Smart and saved filters are
// phase 3.

import Editing
import Foundation
import MusicTheory

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
        if !tags.isEmpty {
            let songTags = Set(song.sidecar.tags.map(Self.fold))
            guard tags.allSatisfy({ songTags.contains(Self.fold($0)) }) else { return false }
        }
        if !proficiencies.isEmpty {
            guard let level = song.sidecar.proficiency, proficiencies.contains(level)
            else { return false }
        }
        if let key {
            guard let written = KeyContext(document: song.document).writtenKey,
                  Self.sameKey(key, written)
            else { return false }
        }
        return true
    }

    /// Splits a typed query into filter tokens and free text, as in the builder's search
    /// field ("ready, upbeat, key G"): comma- or space-separated tokens that name a
    /// proficiency level (`learning`, `ready`, `pro`), a known tag (case-insensitive, also
    /// `#tag`) or `key <name>` become constraints; everything else stays in `text`.
    public static func parse(_ query: String, knownTags: [String]) -> Self {
        // Known tags by folded spelling; the library's spelling wins for display.
        var tagsByFold: [String: String] = [:]
        for tag in knownTags {
            let folded = fold(tag)
            if !folded.isEmpty, tagsByFold[folded] == nil {
                tagsByFold[folded] = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let longestTag = tagsByFold.keys.map { $0.split(separator: " ").count }.max() ?? 0
        var filter = Self()
        var text: [String] = []
        // Commas separate tokens hard: a multi-word tag never spans a comma.
        for segment in query.split(separator: ",") {
            let words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
            var index = 0
            while index < words.count {
                let consumed = token(
                    words[index...],
                    tags: tagsByFold,
                    longestTag: longestTag,
                    into: &filter,
                )
                if consumed == 0 {
                    text.append(words[index])
                    index += 1
                } else {
                    index += consumed
                }
            }
        }
        filter.text = text.joined(separator: " ")
        return filter
    }

    /// Recognises one filter token at the start of `words`, records it in `filter` and
    /// returns how many words it used (0 = free text).
    private static func token(
        _ words: ArraySlice<String>,
        tags: [String: String],
        longestTag: Int,
        into filter: inout Self,
    ) -> Int {
        guard let first = words.first else { return 0 }
        let lowered = first.lowercased()
        // "key G", "key:G", "key: G"
        if lowered == "key" || lowered == "key:", words.count > 1 {
            let name = words[words.startIndex + 1]
            if SongKey(parsing: normalizedKeyName(name)) != nil {
                filter.key = normalizedKeyName(name)
                return 2
            }
        } else if lowered.hasPrefix("key:"), first.count > 4 {
            let name = String(first.dropFirst(4))
            if SongKey(parsing: normalizedKeyName(name)) != nil {
                filter.key = normalizedKeyName(name)
                return 1
            }
        }
        // The longest run of words naming a known tag ("crowd pleaser").
        let hashed = first.hasPrefix("#")
        var length = min(longestTag, words.count)
        while length > 0 {
            var candidate = words.prefix(length).joined(separator: " ")
            if hashed {
                candidate.removeFirst()
            }
            if let tag = tags[fold(candidate)] {
                filter.tags.insert(tag)
                return length
            }
            length -= 1
        }
        if !hashed, let level = Proficiency(rawValue: lowered) {
            filter.proficiencies.insert(level)
            return 1
        }
        return 0
    }

    /// "g" -> "G", "f#m" -> "F#m", "bb" -> "Bb": only the letter is case-folded, so the
    /// "m" suffix keeps its meaning.
    private static func normalizedKeyName(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    /// Case- and width-insensitive form used to compare tags.
    static func fold(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// Whether the filter's key names `written` (enharmonics match: "F#" finds "Gb").
    private static func sameKey(_ name: String, _ written: SongKey) -> Bool {
        guard let wanted = SongKey(parsing: normalizedKeyName(name)) else {
            return fold(name) == fold(written.name)
        }
        return wanted.mode == written.mode
            && wanted.tonic.pitchClass == written.tonic.pitchClass
    }
}
