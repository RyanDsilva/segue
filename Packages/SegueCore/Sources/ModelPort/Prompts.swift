import Foundation

/// The prompts of every task: the spike's validated final design (docs/research/
/// phase3-spikes.md 5.3: split labels and metadata calls, deterministic hints in the prompt,
/// greedy). One source for the FM and MLX adapters. One change since the spike: the labels
/// prompt no longer says every chord-free block is credits (sung tags were labelled `other`
/// on Ryan's real pastes, docs/research/phase3-eval-real-pastes.md).
public enum ModelPrompts {
    // MARK: - Section labels

    public static let labelInstructions = """
    You label the sections of a song chord sheet. The sheet is split into numbered blocks.
    Lyrics may be English or Hindi written in Latin letters (Hinglish). Never translate, correct \
    or repeat any lyric text: output only block numbers and labels.
    For every block give its number and one label:
    intro, verse, prechorus, chorus, bridge, instrumental (guitar tab or a chord-only solo), \
    outro, \
    other (title, credits, ads, website text, notes, comments).
    Notes in brackets after a block number are facts: when a header names the section, use it. \
    A block with no chords at the top or bottom of a sheet that has chords is usually title, \
    credits or website text: other. A short sung line or vocal tag between sections is part of \
    the song: label it like the section it repeats or belongs to. \
    A block whose lyrics repeat an earlier chorus is a chorus; the repeated part of a song without \
    headers is the chorus. A short chord-only block at the start is the intro, at the end the outro.
    """

    /// Part of a sheet (FM chunking, only when MLX is absent).
    public static let chunkInstructions = """
    You label the sections of part of a song chord sheet. The sheet is split into numbered blocks.
    Lyrics may be English or Hindi written in Latin letters (Hinglish). Never translate, correct \
    or repeat any lyric text: output only labels.
    For every block give its number and one label:
    intro, verse, prechorus, chorus, bridge, instrumental (guitar tab or a chord-only solo), \
    outro, \
    other (title, credits, ads, website text, notes, comments).
    A header such as [Chorus], Chorus:, (Chorus), CH, V1, BR names the label. Mukhda means chorus, \
    Antara means verse. A block whose lyrics repeat an earlier chorus is a chorus.
    """

    /// The spike's `Sheet.render(mode: .hints)`: every block (or the blocks in `range`) with
    /// its hints in brackets.
    public static func labelPrompt(_ task: SectionLabelTask, range: Range<Int>? = nil) -> String {
        let blocks = range.map { Array(task.blocks[$0]) } ?? task.blocks
        let total = task.blocks.count
        var output = "Chord sheet with \(total) blocks (Block 0 to Block \(max(total - 1, 0))).\n"
        if range != nil, let first = blocks.first, let last = blocks.last {
            output = "Part of a chord sheet with \(total) blocks; this part has Block "
                + "\(first.index) to Block \(last.index). Label only these blocks.\n"
        }
        for block in blocks {
            output += "\nBlock \(block.index):"
            if !block.hint.isEmpty {
                output += " (\(block.hint))"
            }
            output += "\n" + block.lines.joined(separator: "\n") + "\n"
        }
        return output
    }

    /// The labels call's response budget (spike: 40 + 14 per block).
    public static func labelResponseTokens(blocks: Int) -> Int {
        40 + 14 * blocks
    }

    // MARK: - Metadata

    public static let metadataInstructions = """
    Read the top and bottom of a song chord sheet and extract the song title, artist and key.
    Copy title and artist exactly as written; use an empty string when the sheet does not name \
    one. \
    A line like "X Chords by Y" or "X - Y" gives title X and artist Y. Singer: names the artist. \
    Text may be English or Hindi in Latin letters; never translate it.
    """

    /// The spike's `metadataPrompt()`: top and bottom candidates plus the chord list.
    public static func metadataPrompt(_ task: MetadataTask) -> String {
        var parts: [String] = []
        if !task.topLines.isEmpty {
            parts.append("Top of the sheet:\n" + task.topLines.joined(separator: "\n"))
        }
        if !task.bottomLines.isEmpty {
            parts.append("Bottom of the sheet:\n" + task.bottomLines.joined(separator: "\n"))
        }
        if let last = task.chords.last {
            parts.append("Chords in order (first 40): "
                + task.chords.prefix(40).joined(separator: " ") + "\nLast chord: " + last)
        } else {
            parts.append("The sheet has no chords.")
        }
        return parts.joined(separator: "\n\n")
    }

    public static let metadataResponseTokens = 80

    // MARK: - Ambiguous lines

    public static let ambiguousLineInstructions = """
    Each numbered line below comes from a song chord sheet and is not a lyric line. Give each line \
    one class: note (a performance note such as tuning, strumming pattern, "palm mute", \
    "let ring", \
    or any other text), chords (only chord names, for example G D/F# Em7 Cadd9), tab (guitar \
    tablature such as e|--0--2--|). Text may be English or Hindi in Latin letters; never repeat \
    or translate it.
    """

    public static func ambiguousLinePrompt(_ task: AmbiguousLineTask) -> String {
        task.lines.enumerated().map { number, line in
            var text = "Line \(number): \(line.text)"
            if !line.context.isEmpty {
                text += "\n(around it: " + line.context.joined(separator: " / ") + ")"
            }
            return text
        }.joined(separator: "\n")
    }

    public static func ambiguousLineResponseTokens(lines: Int) -> Int {
        20 + 10 * lines
    }

    // MARK: - Set requests

    /// Spike v3, without energy (R71): the lexicon handles numbers, lengths, keys and tempo.
    public static let setRequestInstructions = """
    Map the words of a musician's request for a set or a song pick to filters. Use "any", an empty \
    string or an empty list for anything the words do not ask for. Numbers, lengths, keys and \
    tempos \
    are handled elsewhere: ignore them.
    minProficiency: "know well", "can play", "nothing I'm still learning", "nothing below Ready" \
    = ready; "know cold" = pro.
    Tags: only tags from the library's list that the words name or clearly mean. "no X" or \
    "skip X" = excludeTags.
    openerTag and closerTag: only when the words ask how the set should start or end ("start \
    with an upbeat one", "finish with a singalong"), a tag from the list.
    """

    public static func setRequestPrompt(_ task: SetRequestTask) -> String {
        let tags = task.libraryTags.isEmpty ? "(none)" : task.libraryTags.joined(separator: ", ")
        return "Tags in this library: \(tags)\nRequest words: \(task.words)"
    }

    public static let setRequestResponseTokens = 120
}

/// Fitting the labels call into a context window (spec 4: budget from runtime values; chunk on
/// block boundaries only when MLX is absent).
public enum LabelChunking {
    /// Margin for the chat template and rounding (spike: 150 tokens).
    public static let margin = 150

    /// `contextSize - instructions - schema - maxResponse - margin`.
    public static func budget(
        contextSize: Int,
        instructionTokens: Int,
        schemaTokens: Int,
        responseTokens: Int,
    ) -> Int {
        contextSize - instructionTokens - schemaTokens - responseTokens - margin
    }

    /// The fallback token estimate where `tokenCount` is unavailable (before macOS 26.4).
    public static func estimatedTokens(_ text: String) -> Int {
        (text.count + 2) / 3
    }

    /// Block ranges for the labels call: the whole sheet when it fits `budget`, else greedy
    /// runs on block boundaries (each run takes at least one block). `cost` is the prompt's
    /// token count for a run of blocks.
    public static func plan(
        blockCount: Int,
        budget: Int,
        cost: (Range<Int>) async throws -> Int,
    ) async rethrows -> [Range<Int>] {
        guard blockCount > 0 else { return [] }
        if try await cost(0 ..< blockCount) <= budget {
            return [0 ..< blockCount]
        }
        var ranges: [Range<Int>] = []
        var start = 0
        while start < blockCount {
            var end = start + 1
            while end < blockCount, try await cost(start ..< end + 1) <= budget {
                end += 1
            }
            ranges.append(start ..< end)
            start = end
        }
        return ranges
    }
}
