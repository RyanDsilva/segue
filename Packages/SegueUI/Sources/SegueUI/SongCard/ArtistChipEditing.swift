import ChordPro
import Foundation
import Library

// P8-8 section 3.3: the artist chip field's rules, pure (the view in ArtistChipField.swift
// only routes keys and clicks here). Nothing here capitalises, re-spells or splits a name
// unless the user asks (Split); typed text is kept exactly as typed after trimming.

/// What a chip field write did, for its one undo step and analytics.
enum ArtistChipEdit: Equatable {
    case add
    case remove
    case reorder
    case split
}

/// One write of the chip field: the new list and what changed.
struct ArtistChipChange: Equatable {
    let artists: [String]
    let edit: ArtistChipEdit
}

enum ArtistChipEditing {
    /// The outcome of committing typed text.
    enum Commit: Equatable {
        /// Nothing typed (after trimming).
        case empty
        /// Already a chip (ignoring case and diacritics): refused, that chip flashes.
        case duplicate(index: Int)
        case added([String])
    }

    /// Commits `typed` as one chip, exactly as typed after trimming ("&" is literal here: a
    /// duo typed by hand stays one chip).
    static func commit(_ typed: String, to artists: [String]) -> Commit {
        guard let name = ArtistNames.cleaned(typed) else { return .empty }
        if let index = artists.firstIndex(where: { same($0, name) }) {
            return .duplicate(index: index)
        }
        return .added(artists + [name])
    }

    /// A typed comma commits what is before it (R173): the finished names and the text
    /// still being typed. Several commas commit several names in order; duplicates and
    /// blanks are skipped.
    static func commas(in text: String, artists: [String]) -> (finished: [String], rest: String)? {
        guard text.contains(",") else { return nil }
        var parts = text.components(separatedBy: ",")
        let rest = parts.removeLast()
        var list = artists
        var finished: [String] = []
        for part in parts {
            if case let .added(next) = commit(part, to: list), let name = next.last {
                list = next
                finished.append(name)
            }
        }
        return (finished, String(rest.drop { $0 == " " }))
    }

    /// Moves the chip at `index` by `offset` places (clamped); nil when it cannot move.
    static func move(_ artists: [String], from index: Int, by offset: Int) -> [String]? {
        let target = index + offset
        guard artists.indices.contains(index), artists.indices.contains(target), offset != 0
        else { return nil }
        var list = artists
        list.swapAt(index, target)
        return list
    }

    /// Moves the chip at `source` to where the chip at `destination` is (a drag).
    static func move(_ artists: [String], from source: Int, to destination: Int) -> [String]? {
        guard artists.indices.contains(source), artists.indices.contains(destination),
              source != destination
        else { return nil }
        var list = artists
        let name = list.remove(at: source)
        list.insert(name, at: destination)
        return list
    }

    /// Whether a chip shows Split: its text splits into two or more names.
    static func canSplit(_ name: String) -> Bool {
        ArtistNames.split(name).didSplit
    }

    /// Replaces the chip at `index` with its split parts, in place; parts already present
    /// elsewhere are dropped (first spelling kept).
    static func split(_ artists: [String], at index: Int) -> [String]? {
        guard artists.indices.contains(index) else { return nil }
        let parts = ArtistNames.split(artists[index]).parts
        guard parts.count > 1 else { return nil }
        var others = artists
        others.remove(at: index)
        let fresh = parts.filter { part in !others.contains { same($0, part) } }
        var list = others
        list.insert(contentsOf: fresh, at: index)
        return list
    }

    /// Up to six library names for `typed`: a `RomanNormalizer.normalize` prefix match
    /// against each name from any word ("shreya goshal" offers "Shreya Ghoshal", "ghoshal"
    /// too). Names already chips are left out; nothing for blank text.
    static func suggestions(for typed: String, applied: [String], known: [String]) -> [String] {
        let query = RomanNormalizer.normalize(typed)
        guard !query.isEmpty else { return [] }
        var result: [String] = []
        for name in known where !applied.contains(where: { same($0, name) }) {
            let words = RomanNormalizer.normalize(name).split(separator: " ").map(String.init)
            let matches = words.indices.contains { start in
                words[start...].joined(separator: " ").hasPrefix(query)
            }
            if matches, !result.contains(where: { same($0, name) }) {
                result.append(name)
            }
            if result.count == 6 {
                break
            }
        }
        return result
    }

    /// Equal ignoring case and diacritics (the duplicate rule).
    static func same(_ lhs: String, _ rhs: String) -> Bool {
        fold(lhs) == fold(rhs)
    }

    private static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
