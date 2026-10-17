// Owner: unit C (Editing). Where the chords and lyric characters of one lyric line are.

/// A lyric line split exactly as `ChordProParser` splits it: `[chord]` tokens and the lyric
/// text runs between them, with UTF-16 source offsets and `Character` lyric offsets.
///
/// Lyric offsets count `Character`s per text run (a run is the text between two chord
/// tokens), the same way `RenderModel` counts them, so both always agree on where a chord
/// sits.
struct LyricLayout: Sendable, Hashable {
    struct Chord: Sendable, Hashable {
        /// UTF-16 range of `[text]`, brackets included, absolute in the snapshot text.
        var range: Range<Int>
        /// The text between the brackets.
        var text: String
        /// Lyric offset the chord sits above.
        var offset: Int
    }

    struct Run: Sendable, Hashable {
        /// Absolute UTF-16 offset of the run's first unit.
        var sourceStart: Int
        var text: String
        /// Lyric offset of the run's first character.
        var lyricStart: Int
        var count: Int
    }

    var chords: [Chord]
    var runs: [Run]
    /// Absolute UTF-16 range of the line content.
    var lineRange: Range<Int>

    /// The lyric text with the chords removed.
    var lyrics: String {
        runs.map(\.text).joined()
    }

    /// Number of lyric characters (sum of per-run counts).
    var lyricCount: Int {
        runs.last.map { $0.lyricStart + $0.count } ?? 0
    }

    /// Scans `text` (one line's content) starting at absolute UTF-16 offset `start`.
    init(line text: String, start: Int) {
        lineRange = start ..< start + text.utf16.count
        var chords: [Chord] = []
        var runs: [Run] = []
        var lyricOffset = 0
        let utf8 = text.utf8
        var textStart = utf8.startIndex
        var index = utf8.startIndex
        func flushRun(upTo end: String.Index) {
            guard textStart < end else { return }
            let run = String(text[textStart ..< end])
            let count = run.count
            runs.append(Run(
                sourceStart: start + text.utf16.distance(from: text.startIndex, to: textStart),
                text: run,
                lyricStart: lyricOffset,
                count: count,
            ))
            lyricOffset += count
        }
        while index < utf8.endIndex {
            guard utf8[index] == UInt8(ascii: "[") else {
                index = utf8.index(after: index)
                continue
            }
            var scan = utf8.index(after: index)
            while scan < utf8.endIndex, utf8[scan] != UInt8(ascii: "]"),
                  utf8[scan] != UInt8(ascii: "[")
            {
                scan = utf8.index(after: scan)
            }
            guard scan < utf8.endIndex, utf8[scan] == UInt8(ascii: "]") else {
                index = utf8.index(after: index)
                continue
            }
            flushRun(upTo: index)
            let after = utf8.index(after: scan)
            let lower = start + text.utf16.distance(from: text.startIndex, to: index)
            let upper = start + text.utf16.distance(from: text.startIndex, to: after)
            chords.append(Chord(
                range: lower ..< upper,
                text: String(text[utf8.index(after: index) ..< scan]),
                offset: lyricOffset,
            ))
            index = after
            textStart = after
        }
        flushRun(upTo: utf8.endIndex)
        self.chords = chords
        self.runs = runs
    }

    /// Absolute UTF-16 offset of lyric offset `offset`, after any chords sitting there;
    /// `nil` when out of range.
    func sourceOffset(ofLyricOffset offset: Int) -> Int? {
        guard offset >= 0, offset <= lyricCount else { return nil }
        if let run = runs.first(where: { offset < $0.lyricStart + $0.count }) {
            let characters = run.text.prefix(offset - run.lyricStart)
            return run.sourceStart + characters.utf16.count
        }
        return lineRange.upperBound
    }

    /// Lyric offset at an absolute UTF-16 offset inside the line. Inside a chord token it
    /// snaps to the chord's lyric offset.
    func lyricOffset(atSourceOffset source: Int) -> Int {
        if let chord = chords
            .first(where: { $0.range.lowerBound < source && source < $0.range.upperBound })
        {
            return chord.offset
        }
        var result = 0
        for run in runs where run.sourceStart < source {
            let within = source - run.sourceStart
            if within >= run.text.utf16.count {
                result = run.lyricStart + run.count
            } else {
                let utf16 = run.text.utf16
                let target = utf16.index(utf16.startIndex, offsetBy: within)
                // Round down to a character boundary.
                let boundary = run.text[..<target].count
                let rounded = run.text.index(run.text.startIndex, offsetBy: boundary)
                result = run.lyricStart + (rounded > target ? boundary - 1 : boundary)
            }
        }
        return result
    }
}

/// A lyric line as an editable value: lyric characters plus chords at lyric offsets.
/// Rendering it reproduces the source line exactly when nothing changed.
struct LyricLineModel: Sendable, Hashable {
    struct Chord: Sendable, Hashable {
        var text: String
        var offset: Int
    }

    var lyrics: [Character]
    /// In source order (offsets non-decreasing), so stacked chords keep their order.
    var chords: [Chord]

    init(_ layout: LyricLayout) {
        // Characters per run, matching the lyric offsets (a combining mark right after a
        // chord would merge into the previous run's last character in the joined string).
        lyrics = layout.runs.flatMap { Array($0.text) }
        chords = layout.chords.map { Chord(text: $0.text, offset: $0.offset) }
    }

    init(lyrics: [Character], chords: [Chord]) {
        self.lyrics = lyrics
        self.chords = chords
    }

    /// Source text of the line: each chord before the character it sits above, stacked
    /// chords in order, chords at the end after the last character. Also returns, in UTF-16
    /// offsets into the text, where each chord token ends (by index in `chords`) and where
    /// each lyric offset 0 ... count starts (after the chords sitting there).
    func render() -> Rendered {
        var text = ""
        var length = 0
        var chordEnds = Array(repeating: 0, count: chords.count)
        var lyricStarts: [Int] = []
        lyricStarts.reserveCapacity(lyrics.count + 1)
        let ordered = chords.indices.sorted {
            (chords[$0].offset, $0) < (chords[$1].offset, $1)
        }
        var next = 0
        func emitChords(through offset: Int) {
            while next < ordered.count, chords[ordered[next]].offset <= offset {
                let token = "[" + chords[ordered[next]].text + "]"
                text += token
                length += token.utf16.count
                chordEnds[ordered[next]] = length
                next += 1
            }
        }
        for (index, character) in lyrics.enumerated() {
            emitChords(through: index)
            lyricStarts.append(length)
            text.append(character)
            length += character.utf16.count
        }
        emitChords(through: Int.max)
        lyricStarts.append(length)
        return Rendered(text: text, chordEnds: chordEnds, lyricStarts: lyricStarts)
    }

    struct Rendered {
        var text: String
        var chordEnds: [Int]
        var lyricStarts: [Int]
    }

    /// Inserts a chord after any chords already at `offset`.
    mutating func insert(_ text: String, at offset: Int) {
        let position = chords.lastIndex { $0.offset <= offset }.map { $0 + 1 } ?? 0
        chords.insert(Chord(text: text, offset: offset), at: position)
    }
}
