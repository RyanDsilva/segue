// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit D.
//
// Phase 2 simple filtering: tags, proficiency, key. Phase 3 (P3-6) extends it compatibly
// with the conditions a saved `SmartFilter` compiles to (any / none tags, several keys,
// tempo and length ranges, never played, missing essentials); their defaults constrain nothing, so
// phase 2
// callers see no change.

import ChordPro
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
    /// At least one of these tags must be present (case-insensitive); empty = no constraint.
    public var anyTags: Set<String>
    /// None of these tags may be present (case-insensitive).
    public var excludedTags: Set<String>
    /// The written key must be one of these (compared like `key`); empty = no constraint.
    public var keys: Set<String>
    /// `{tempo}` in BPM within these bounds; a song without a tempo never matches.
    public var tempo: Bounds?
    /// `{duration}` in seconds within these bounds; a song without a length never matches
    /// (R91).
    public var length: Bounds?
    /// "Never played": when set, the song must not be among these played songs (the play
    /// snapshot a `SmartFilter` compiles in, so `matches(_:)` needs no other input).
    public var playedSongs: Set<SongID>?
    /// Only songs missing a set essential (key, length or tempo; `SongEssentials`, R110).
    public var missingEssentials: Bool

    public init(
        text: String = "",
        tags: Set<String> = [],
        proficiencies: Set<Proficiency> = [],
        key: String? = nil,
        anyTags: Set<String> = [],
        excludedTags: Set<String> = [],
        keys: Set<String> = [],
        tempo: Bounds? = nil,
        length: Bounds? = nil,
        playedSongs: Set<SongID>? = nil,
        missingEssentials: Bool = false,
    ) {
        self.text = text
        self.tags = tags
        self.proficiencies = proficiencies
        self.key = key
        self.anyTags = anyTags
        self.excludedTags = excludedTags
        self.keys = keys
        self.tempo = tempo
        self.length = length
        self.playedSongs = playedSongs
        self.missingEssentials = missingEssentials
    }

    /// Inclusive numeric bounds; a nil side is open.
    public struct Bounds: Sendable, Equatable {
        public var lower: Double?
        public var upper: Double?

        public init(lower: Double? = nil, upper: Double? = nil) {
            self.lower = lower
            self.upper = upper
        }

        /// Whether `value` lies within the bounds (both ends included).
        public func contains(_ value: Double) -> Bool {
            if let lower, value < lower {
                return false
            }
            if let upper, value > upper {
                return false
            }
            return true
        }
    }

    /// True when no constraint is set (the text may still be non-empty).
    public var hasConstraints: Bool {
        !tags.isEmpty || !proficiencies.isEmpty || key != nil || !anyTags.isEmpty
            || !excludedTags.isEmpty || !keys.isEmpty || tempo != nil || length != nil
            || playedSongs != nil || missingEssentials
    }

    /// Whether `song` satisfies every constraint (not `text`).
    public func matches(_ song: SongRecord) -> Bool {
        if !proficiencies.isEmpty {
            guard let level = song.sidecar.proficiency, proficiencies.contains(level)
            else { return false }
        }
        if let playedSongs, playedSongs.contains(song.id) {
            return false
        }
        if missingEssentials, !SongEssentials.isMissingAny(in: song.document) {
            return false
        }
        return matchesTags(song) && matchesKey(song) && matchesNumbers(song.document.metadata)
    }

    private func matchesTags(_ song: SongRecord) -> Bool {
        guard !tags.isEmpty || !anyTags.isEmpty || !excludedTags.isEmpty else { return true }
        let songTags = Set(song.sidecar.tags.map(Self.fold))
        let has = { (tag: String) in songTags.contains(Self.fold(tag)) }
        return tags.allSatisfy(has)
            && (anyTags.isEmpty || anyTags.contains(where: has))
            && !excludedTags.contains(where: has)
    }

    private func matchesKey(_ song: SongRecord) -> Bool {
        guard key != nil || !keys.isEmpty else { return true }
        guard let written = KeyContext(document: song.document).writtenKey else { return false }
        if let key, !Self.sameKey(key, written) {
            return false
        }
        return keys.isEmpty || keys.contains { Self.sameKey($0, written) }
    }

    /// Tempo and length: a song without the value never matches a set range.
    private func matchesNumbers(_ metadata: Metadata) -> Bool {
        if let tempo {
            guard let bpm = metadata.tempo, tempo.contains(bpm) else { return false }
        }
        if let length {
            guard let seconds = metadata.duration, length.contains(seconds) else { return false }
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
