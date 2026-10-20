import Foundation
import Ingest
import MusicTheory

// P3-A part 2: run the harness on the app's real deterministic pipeline (P3-1's
// `IngestPipeline`) instead of the spike's stand-in segmenter. `SPIKE_SEGMENTER=ingest`
// switches `loadSheets`; `SPIKE_INGEST_DUMP=<path>` also writes what code decided per block
// (role, label source, code label, hint) and the code metadata, so the scorer can merge code
// and model decisions the way P3-2's refinement merge does. The dump holds no lyric text.

extension Sheet {
    init(name: String, ingest result: IngestResult) {
        self.name = name
        blocks = result.blocks.map { block in
            let summary = block.hints.summary
            return Block(index: block.index, lines: block.lines.map(\.text), hint: summary.isEmpty ? nil : summary)
        }
        ingestMetadataPrompt = Sheet.metadataPrompt(result.questions.metadataCandidates)
        usesIngest = true
    }

    /// The spike's metadata view, built from P3-1's `MetadataCandidates`.
    static func metadataPrompt(_ candidates: MetadataCandidates?) -> String? {
        guard let candidates else { return nil }
        var parts: [String] = []
        if !candidates.topLines.isEmpty {
            parts.append("Top of the sheet:\n" + candidates.topLines.joined(separator: "\n"))
        }
        if !candidates.bottomLines.isEmpty {
            parts.append("Bottom of the sheet:\n" + candidates.bottomLines.joined(separator: "\n"))
        }
        if parts.isEmpty, candidates.chords.isEmpty { return nil }
        if let last = candidates.chords.last {
            parts.append("Chords in order (first 40): " + candidates.chords.prefix(40).joined(separator: " ")
                + "\nLast chord: " + last)
        } else {
            parts.append("The sheet has no chords.")
        }
        return parts.joined(separator: "\n\n")
    }
}

/// What code decided for one paste (no lyric text).
struct IngestDump: Codable {
    struct BlockInfo: Codable {
        var index: Int
        var role: String
        var labelSource: String
        var codeLabel: String?
        var hint: String
        var sameLyricsAs: Int?
        var lineCount: Int
    }

    var name: String
    var format: String
    var blocks: [BlockInfo]
    var unheadedBlocks: [Int]
    var codeTitle: String?
    var codeArtists: [String]
    var statedKey: String?
    var detectedKey: String?
    var keyAmbiguous: Bool
    var topTwo: [String]
    var hasMetadataCandidates: Bool
    /// Top + bottom candidate lines (0 means the metadata call would see chords only).
    var metadataLineCount: Int

    init(name: String, result: IngestResult) {
        self.name = name
        format = result.format.rawValue
        blocks = result.blocks.map { block in
            BlockInfo(
                index: block.index, role: block.role.rawValue, labelSource: block.labelSource.rawValue,
                codeLabel: block.label?.rawValue, hint: block.hints.summary,
                sameLyricsAs: block.hints.sameLyricsAs, lineCount: block.lines.count)
        }
        unheadedBlocks = result.questions.unheadedBlocks
        codeTitle = result.metadata.title
        codeArtists = result.metadata.artists
        statedKey = result.keyInference.stated?.name
        detectedKey = result.keyInference.detection?.key.name
        keyAmbiguous = result.keyInference.isAmbiguous
        topTwo = result.keyInference.topTwo.map(\.name)
        hasMetadataCandidates = result.questions.metadataCandidates != nil
        metadataLineCount = (result.questions.metadataCandidates?.topLines.count ?? 0)
            + (result.questions.metadataCandidates?.bottomLines.count ?? 0)
    }
}

func loadIngestSheets(dir: String, files: [String]) throws -> [Sheet] {
    var dumps: [IngestDump] = []
    let sheets = try files.map { file in
        let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(file))
        let name = String(file.dropLast(4))
        let result = IngestPipeline.ingest(String(decoding: data, as: UTF8.self), origin: .paste)
        dumps.append(IngestDump(name: name, result: result))
        return Sheet(name: name, ingest: result)
    }
    if let path = ProcessInfo.processInfo.environment["SPIKE_INGEST_DUMP"] {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(Dictionary(uniqueKeysWithValues: dumps.map { ($0.name, $0) }))
            .write(to: URL(fileURLWithPath: path))
    }
    return sheets
}
