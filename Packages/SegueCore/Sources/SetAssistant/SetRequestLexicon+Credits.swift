// P8-8 section 3.5.2 (R172, R173): artists and movies / albums in a set request. "by
// <artist>" or "<artist> songs" makes an artist chip, "from <movie>" (after smart filter
// names), "from the movie <movie>" or "<movie> songs" an album chip, a negator before any
// of them its exclusion. Names come from the library only (code finds names or nothing; the
// model pass never proposes these chips), folded like tags.

import Foundation
import Library

/// The library's artist and album names, keyed like tag names (`SetRequestLexicon.keys`).
struct CreditNames: Sendable {
    /// Full artist names (each `ArtistNames.split` part, plus a legacy combined value).
    private var artists: [String: String] = [:]
    /// The leading words of an artist name; nil when two names share them ("shreya").
    private var artistLeads: [String: String?] = [:]
    private var albums: [String: String] = [:]
    private(set) var longest = 1

    init(artists artistValues: [String], albums albumNames: [String]) {
        var names: [String] = []
        for value in artistValues {
            let parts = SongFilter.artistParts(value)
            names += parts
            if parts.count > 1 {
                names.append(value.trimmingCharacters(in: .whitespaces))
            }
        }
        for name in names {
            let words = SetRequestLexicon.nameWords(name)
            guard !words.isEmpty else { continue }
            longest = max(longest, words.count)
            for key in SetRequestLexicon.keys(words) where artists[key] == nil {
                artists[key] = name
            }
        }
        for name in names {
            let words = SetRequestLexicon.nameWords(name)
            guard words.count > 1 else { continue }
            for count in 1 ..< words.count {
                for key in SetRequestLexicon.keys(Array(words.prefix(count))) {
                    switch artistLeads[key] {
                    case nil: artistLeads[key] = .some(name)
                    case let .some(existing?) where SetRequest.fold(existing) != SetRequest
                        .fold(name): artistLeads[key] = .some(nil)
                    default: break
                    }
                }
            }
        }
        for name in albumNames {
            let words = SetRequestLexicon.nameWords(name)
            guard !words.isEmpty else { continue }
            longest = max(longest, words.count)
            for key in SetRequestLexicon.keys(words) where albums[key] == nil {
                albums[key] = name.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    var isEmpty: Bool {
        artists.isEmpty && albums.isEmpty
    }

    /// The artist a run of words at `index` names (a full name, else the leading words of
    /// exactly one name), longest first, and how many words it took.
    func artist(in scan: Scan, at index: Int) -> (String, Int)? {
        longest(in: scan, at: index) { key in
            artists[key] ?? artistLeads[key] ?? nil
        }
    }

    func album(in scan: Scan, at index: Int) -> (String, Int)? {
        longest(in: scan, at: index) { albums[$0] }
    }

    private func longest(
        in scan: Scan,
        at index: Int,
        lookup: (String) -> String?,
    ) -> (String, Int)? {
        guard index < scan.tokens.count else { return nil }
        var length = min(longest, scan.tokens.count - index)
        while length > 0 {
            let range = index ..< index + length
            if !range.contains(where: { scan.used[$0] || scan.tokens[$0].isComma }) {
                let words = range.map { scan.tokens[$0].word }
                if let found = SetRequestLexicon.keys(words).lazy.compactMap(lookup).first {
                    return (found, length)
                }
            }
            length -= 1
        }
        return nil
    }
}

extension SetRequestLexicon {
    private static let songWords: Set = ["songs", "song", "gaane", "gane", "numbers"]
    private static let albumWords: Set = ["movie", "film", "album", "picture"]

    /// Reads artist and album names. Runs before `readNames`, leaving to it every run a tag
    /// or a smart filter claims at least as long ("hindi songs" stays a tag).
    func readCredits(_ scan: inout Scan) {
        guard !credits.isEmpty else { return }
        var index = 0
        while index < scan.tokens.count {
            guard !scan.used[index] else {
                index += 1
                continue
            }
            if let end = readCredit(&scan, at: index) {
                index = end
            } else {
                index += 1
            }
        }
    }

    /// One credit starting at `index`; the index after it, or nil when none starts there.
    private func readCredit(_ scan: inout Scan, at index: Int) -> Int? {
        let word = scan.tokens[index].word
        if word == "by", let (name, length) = credits.artist(in: scan, at: index + 1) {
            return claim(&scan, index ..< index + 1 + length, artist: name)
        }
        if word == "from" {
            // A smart filter name wins ("from Wedding set"); readNames claims it.
            guard longestFilter(in: scan, at: index + 1) == nil else { return nil }
            var cursor = index + 1
            if scan.word(at: cursor) == "the" {
                cursor += 1
            }
            if let next = scan.word(at: cursor), Self.albumWords.contains(next) {
                cursor += 1
            }
            if let (name, length) = credits.album(in: scan, at: cursor) {
                return claim(&scan, index ..< cursor + length, album: name)
            }
            return nil
        }
        let tagLength = longestTag(in: scan, at: index)?.1 ?? 0
        let negated = negatorBefore(index, in: scan) != nil
        if let (name, length) = credits.artist(in: scan, at: index), length > tagLength {
            let songs = scan.word(at: index + length).map(Self.songWords.contains) ?? false
            if songs || negated {
                return claim(&scan, index ..< index + length + (songs ? 1 : 0), artist: name)
            }
        }
        if let (name, length) = credits.album(in: scan, at: index), length > tagLength {
            let songs = scan.word(at: index + length).map(Self.songWords.contains) ?? false
            if songs || negated {
                return claim(&scan, index ..< index + length + (songs ? 1 : 0), album: name)
            }
        }
        return nil
    }

    private func claim(_ scan: inout Scan, _ range: Range<Int>, artist name: String) -> Int {
        let negator = negatorBefore(range.lowerBound, in: scan)
        let claimed = (negator ?? range.lowerBound) ..< range.upperBound
        scan.claim(claimed, negator == nil ? .artist(name) : .excludeArtist(name))
        return claimed.upperBound
    }

    private func claim(_ scan: inout Scan, _ range: Range<Int>, album name: String) -> Int {
        let negator = negatorBefore(range.lowerBound, in: scan)
        let claimed = (negator ?? range.lowerBound) ..< range.upperBound
        scan.claim(claimed, negator == nil ? .album(name) : .excludeAlbum(name))
        return claimed.upperBound
    }
}
