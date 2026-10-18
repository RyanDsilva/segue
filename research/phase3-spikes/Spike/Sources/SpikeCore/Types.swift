import Foundation
import FoundationModels

public enum Vocab {
    public static let labels = [
        "intro", "verse", "prechorus", "chorus", "bridge", "instrumental", "outro", "other",
    ]
    public static let roots = [
        "C", "C#", "Db", "D", "Eb", "E", "F", "F#", "Gb", "G", "Ab", "A", "Bb", "B",
    ]
    public static let keys: [String] = roots + roots.map { $0 + "m" }
    public static let keysOrUnknown: [String] = keys + ["unknown"]
    public static let tags = [
        "acoustic", "ballad", "crowd pleaser", "singalong", "original", "cover", "hindi",
        "wedding", "rock", "upbeat",
    ]
    public static let proficiency = ["any", "learning", "ready", "pro"]
    public static let opener = ["any", "low", "medium", "high"]
    public static let closer = ["any", "low", "medium", "high", "crowd pleaser"]
}

@Generable
public struct BlockLabel: Codable, Sendable {
    @Guide(description: "Block number as shown in the sheet")
    public var block: Int
    @Guide(description: "Section kind of this block", .anyOf(Vocab.labels))
    public var label: String
}

@Generable
public struct PasteEnrichment: Codable, Sendable {
    @Guide(description: "Song title exactly as written in the sheet, or null if no title is written")
    public var title: String?
    @Guide(description: "Artist, band or singer exactly as written in the sheet, or null if none is written")
    public var artist: String?
    @Guide(description: "Key of the song: the stated key if the sheet states one, else your best guess from the chords", .anyOf(Vocab.keysOrUnknown))
    public var key: String
    @Guide(description: "Exactly one entry per block, in block order")
    public var blocks: [BlockLabel]
}

@Generable
public struct SongMetadata: Codable, Sendable {
    @Guide(description: "Song title exactly as written, or an empty string if no title is written")
    public var title: String
    @Guide(description: "Artist, band or singer exactly as written, or an empty string if none is written")
    public var artist: String
    @Guide(description: "Key of the song: the stated key (Key:, Scale:) if any, else your best guess from the chords, or unknown if there are no chords", .anyOf(Vocab.keysOrUnknown))
    public var key: String
}

/// Chunk variant: labels only (metadata asked only in the first chunk).
@Generable
public struct BlockLabelsOnly: Codable, Sendable {
    @Guide(description: "Exactly one entry per block, in block order")
    public var blocks: [BlockLabel]
}

@Generable
public struct SetRequestParse: Codable, Sendable {
    @Guide(description: "Total set length in minutes if the user gives a length (an hour = 60), else null")
    public var targetMinutes: Int?
    @Guide(description: "Number of songs only if the user states a count, else null")
    public var songCount: Int?
    @Guide(description: "Minimum proficiency", .anyOf(Vocab.proficiency))
    public var minProficiency: String
    @Guide(description: "Lowest song energy 1-5, or null", .range(1...5))
    public var energyMin: Int?
    @Guide(description: "Highest song energy 1-5, or null", .range(1...5))
    public var energyMax: Int?
    @Guide(description: "Energy of the opening song", .anyOf(Vocab.opener))
    public var openerEnergy: String
    @Guide(description: "What the closing song should be", .anyOf(Vocab.closer))
    public var closer: String
    @Guide(description: "Tags the songs must have", .element(.anyOf(Vocab.tags)))
    public var includeTags: [String]
    @Guide(description: "Tags the songs must not have", .element(.anyOf(Vocab.tags)))
    public var excludeTags: [String]
    @Guide(description: "Allowed keys, empty if the user names none", .element(.anyOf(Vocab.keys)))
    public var keys: [String]
    @Guide(description: "Minimum tempo in BPM, or null")
    public var tempoMinBPM: Int?
    @Guide(description: "Maximum tempo in BPM, or null")
    public var tempoMaxBPM: Int?
}

public enum Prompts {
    public static let pasteInstructions = """
        You label the sections of a song chord sheet. The sheet is split into numbered blocks.
        Lyrics may be English or Hindi written in Latin letters (Hinglish). Never translate, correct \
        or repeat any lyric text: output only labels and metadata.
        For every block give its number and one label:
        intro, verse, prechorus, chorus, bridge, instrumental (guitar tab or a chord-only solo), outro, \
        other (title, credits, ads, website text, notes, comments).
        A header such as [Chorus], Chorus:, (Chorus), CH, V1, BR names the label. Mukhda means chorus, \
        Antara means verse. A block whose lyrics repeat an earlier chorus is a chorus.
        Title and artist: only if written in the sheet, else null. Key: the stated key (Key:, Scale:) \
        if any, else guess from the chords.
        """

    public static let labelInstructions = """
        You label the sections of a song chord sheet. The sheet is split into numbered blocks.
        Lyrics may be English or Hindi written in Latin letters (Hinglish). Never translate, correct \
        or repeat any lyric text: output only block numbers and labels.
        For every block give its number and one label:
        intro, verse, prechorus, chorus, bridge, instrumental (guitar tab or a chord-only solo), outro, \
        other (title, credits, ads, website text, notes, comments).
        Notes in brackets after a block number are facts: when a header names the section, use it. \
        A block with no chords in a sheet that has chords is usually title, credits or website text: other. \
        A block whose lyrics repeat an earlier chorus is a chorus; the repeated part of a song without \
        headers is the chorus. A short chord-only block at the start is the intro, at the end the outro.
        """

    public static let metadataInstructions = """
        Read the top and bottom of a song chord sheet and extract the song title, artist and key.
        Copy title and artist exactly as written; use an empty string when the sheet does not name one. \
        A line like "X Chords by Y" or "X - Y" gives title X and artist Y. Singer: names the artist. \
        Text may be English or Hindi in Latin letters; never translate it.
        """

    public static let chunkInstructions = """
        You label the sections of part of a song chord sheet. The sheet is split into numbered blocks.
        Lyrics may be English or Hindi written in Latin letters (Hinglish). Never translate, correct \
        or repeat any lyric text: output only labels.
        For every block give its number and one label:
        intro, verse, prechorus, chorus, bridge, instrumental (guitar tab or a chord-only solo), outro, \
        other (title, credits, ads, website text, notes, comments).
        A header such as [Chorus], Chorus:, (Chorus), CH, V1, BR names the label. Mukhda means chorus, \
        Antara means verse. A block whose lyrics repeat an earlier chorus is a chorus.
        """

    public static let setInstructions = """
        Turn a musician's request for a set or a song pick into filters. Leave a field null, empty \
        or "any" unless the request asks for it.
        Length: "an hour" = 60, "1.5 hours" = 90, "two hours" = 120 minutes. songCount only for an \
        explicit number of songs.
        minProficiency: "know well", "can play", "nothing I'm still learning", "nothing below Ready" \
        = ready; "know cold" = pro; otherwise any.
        Tags: use a tag only when the request names it: acoustic, ballad, crowd pleaser, singalong, \
        original, cover, hindi, wedding, rock, upbeat. "no X" / "skip X" = excludeTags.
        Energy (1-5): "high energy" = energyMin 4; "mellow", "chill", "low energy" = energyMax 2.
        openerEnergy: "upbeat start", "start strong" = high; "start soft" = low.
        closer: "finish big" = high; "end with a crowd pleaser" = crowd pleaser.
        keys: named keys only, "E minor" = Em. Tempo in BPM only if numbers are given.
        """

    public static let setRequests: [String] = [
        "45 min set, mostly songs I know well, upbeat start",
        "something upbeat in G I know well",
        "an hour of acoustic stuff, nothing I'm still learning",
        "10 songs for a wedding, end with a crowd pleaser",
        "30 minutes of hindi songs I know cold",
        "chill ballads under 90 bpm",
        "90 minute rock set, high energy throughout, no covers",
        "quick 20 min opener set, start soft and build up",
        "two hour gig, originals only, songs in D or A",
        "singalongs between 100 and 130 bpm",
        "give me 5 mellow songs in E minor",
        "40 mins, skip the hindi ones, finish big",
        "background dinner music, 1.5 hours, low energy, anything I can play",
        "kuch romantic hindi gaane, 25 minute",
        "pub night, 75 minutes, crowd pleasers and singalongs, nothing below Ready",
    ]
}

/// One measured model call, written as a JSON line.
public struct CallRecord: Codable, Sendable {
    public var runner: String
    public var model: String
    public var task: String
    public var item: String
    public var variant: String
    public var chunk: Int
    public var chunks: Int
    public var ok: Bool
    public var errorKind: String?
    public var errorDetail: String?
    public var latencyMs: Double
    public var promptTokens: Int?
    public var instructionTokens: Int?
    public var schemaTokens: Int?
    public var transcriptTokens: Int?
    public var outputTokens: Int?
    public var contextSize: Int?
    public var peakMemoryMB: Double?
    public var output: String?

    public init(runner: String, model: String, task: String, item: String, variant: String) {
        self.runner = runner
        self.model = model
        self.task = task
        self.item = item
        self.variant = variant
        chunk = 0
        chunks = 1
        ok = false
        latencyMs = 0
    }
}

public final class JSONLWriter: @unchecked Sendable {
    let handle: FileHandle
    public init(path: String) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    }
    public func write(_ record: CallRecord) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if var data = try? enc.encode(record) {
            data.append(0x0A)
            handle.write(data)
        }
    }
}

public func schemaJSON(_ schema: GenerationSchema) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return (try? String(data: enc.encode(schema), encoding: .utf8)) ?? "{}"
}

/// Labels schema whose array length is pinned to the number of blocks (no runaway / missing entries).
public func exactLabelsSchema(blocks n: Int) throws -> GenerationSchema {
    let item = DynamicGenerationSchema(type: BlockLabel.self)
    let root = DynamicGenerationSchema(
        name: "BlockLabelsOnly",
        properties: [
            .init(name: "blocks", description: "Exactly one entry per block, in block order",
                  schema: DynamicGenerationSchema(arrayOf: item, minimumElements: n, maximumElements: n))
        ])
    return try GenerationSchema(root: root, dependencies: [])
}

/// v2: no Optionals (FM silently omits optional fields under greedy decoding), 0 = not given,
/// bounded arrays (FM ran away enumerating every key), short schema.
@Generable
public struct SetRequestV2: Codable, Sendable {
    @Guide(description: "Set length in minutes, 0 if not given", .range(0...300))
    public var minutes: Int
    @Guide(description: "Number of songs, 0 if no count is given", .range(0...60))
    public var songCount: Int
    @Guide(description: "Minimum proficiency", .anyOf(Vocab.proficiency))
    public var minProficiency: String
    @Guide(description: "Energy wanted for the songs", .anyOf(["any", "low", "high"]))
    public var energy: String
    @Guide(description: "Energy of the opening song", .anyOf(Vocab.opener))
    public var opener: String
    @Guide(description: "What the closing song should be", .anyOf(Vocab.closer))
    public var closer: String
    @Guide(description: "Tags named in the request", .maximumCount(4), .element(.anyOf(Vocab.tags)))
    public var includeTags: [String]
    @Guide(description: "Tags the request excludes", .maximumCount(4), .element(.anyOf(Vocab.tags)))
    public var excludeTags: [String]
    @Guide(description: "Keys named in the request", .maximumCount(4), .element(.anyOf(Vocab.keys)))
    public var keys: [String]
    @Guide(description: "Minimum BPM, 0 if not given", .range(0...300))
    public var minBPM: Int
    @Guide(description: "Maximum BPM, 0 if not given", .range(0...300))
    public var maxBPM: Int
}

extension Prompts {
    public static let setInstructionsV2 = """
        Turn a musician's request for a set or a song pick into filters. Use 0, "any" or an empty \
        list for anything the request does not ask for.
        Length: "an hour" = 60, "1.5 hours" = 90, "two hours" = 120 minutes. songCount only for an \
        explicit number of songs.
        minProficiency: "know well", "can play", "nothing I'm still learning", "nothing below Ready" \
        = ready; "know cold" = pro.
        Tags: only tags the request names: acoustic, ballad, crowd pleaser, singalong, original, \
        cover, hindi, wedding, rock, upbeat. "no X" or "skip X" = excludeTags.
        energy: "high energy" = high; "mellow", "chill", "low energy" = low.
        opener: "upbeat start", "start strong" = high; "start soft" = low.
        closer: "finish big" = high; "end with a crowd pleaser" = crowd pleaser.
        keys: only keys the request names, "E minor" = Em.
        """
}

/// v3: code parses numbers/keys; the model only maps fuzzy phrases.
@Generable
public struct SetRequestV3: Codable, Sendable {
    @Guide(description: "Minimum proficiency", .anyOf(Vocab.proficiency))
    public var minProficiency: String
    @Guide(description: "Energy wanted for the songs", .anyOf(["any", "low", "high"]))
    public var energy: String
    @Guide(description: "Energy of the opening song", .anyOf(Vocab.opener))
    public var opener: String
    @Guide(description: "What the closing song should be", .anyOf(Vocab.closer))
    public var closer: String
    @Guide(description: "Tags named in the request", .maximumCount(4), .element(.anyOf(Vocab.tags)))
    public var includeTags: [String]
    @Guide(description: "Tags the request excludes", .maximumCount(4), .element(.anyOf(Vocab.tags)))
    public var excludeTags: [String]
}

public struct NumericRequest: Codable, Sendable {
    public var minutes = 0, songCount = 0, minBPM = 0, maxBPM = 0
    public var keys: [String] = []

    public init(_ text: String) {
        let t = text.lowercased()
        let words = ["one": 1.0, "an": 1, "a": 1, "two": 2, "three": 3, "half an": 0.5]
        if let m = t.firstMatch(of: /(\d+(?:\.\d+)?)\s*(?:min|mins|minute|minutes)\b/) { minutes = Int(Double(m.1)!) }
        else if let m = t.firstMatch(of: /(\d+(?:\.\d+)?)\s*(?:hour|hours|hr|hrs)\b/) { minutes = Int(Double(m.1)! * 60) }
        else if let m = t.firstMatch(of: /\b(one|an|a|two|three)\s+(?:hour|hours)\b/) { minutes = Int(words[String(m.1)]! * 60) }
        if let m = t.firstMatch(of: /\b(\d+)\s+(?:songs|tunes|tracks)\b/) { songCount = Int(m.1)! }
        else if let m = t.firstMatch(of: /\b(\d+)\s+\w+\s+(?:songs|tunes)\b/) { songCount = Int(m.1)! }
        if let m = t.firstMatch(of: /between\s+(\d+)\s+and\s+(\d+)\s*bpm/) { minBPM = Int(m.1)!; maxBPM = Int(m.2)! }
        else if let m = t.firstMatch(of: /(?:under|below|less than)\s+(\d+)\s*bpm/) { maxBPM = Int(m.1)! }
        else if let m = t.firstMatch(of: /(?:over|above|more than)\s+(\d+)\s*bpm/) { minBPM = Int(m.1)! }
        // keys: "in G", "in D or A", "in E minor"; case-sensitive on original text
        if let m = text.firstMatch(of: /\bin\s+([A-G][#b]?(?:\s*(?:minor|major|m))?(?:\s*(?:,|or|and)\s*[A-G][#b]?(?:\s*(?:minor|major|m))?)*)\b/) {
            for k in String(m.1).split(whereSeparator: { $0 == "," }).flatMap({ $0.components(separatedBy: " or ") }).flatMap({ $0.components(separatedBy: " and ") }) {
                var s = k.trimmingCharacters(in: .whitespaces)
                s = s.replacingOccurrences(of: " minor", with: "m").replacingOccurrences(of: " major", with: "")
                if Vocab.keys.contains(s) { keys.append(s) }
            }
        }
    }
}

extension Prompts {
    public static let setInstructionsV3 = """
        Map a musician's request for a set or a song pick to filters. Use "any" or an empty list for \
        anything the request does not ask for. Numbers, lengths and keys are handled elsewhere: ignore them.
        minProficiency: "know well", "can play", "nothing I'm still learning", "nothing below Ready" \
        = ready; "know cold" = pro.
        Tags: only tags the request names: acoustic, ballad, crowd pleaser, singalong, original, \
        cover, hindi, wedding, rock, upbeat. "no X" or "skip X" = excludeTags.
        energy: "high energy" = high; "mellow", "chill", "low energy" = low.
        opener: "upbeat start", "start strong" = high; "start soft" = low.
        closer: "finish big" = high; "end with a crowd pleaser" = crowd pleaser.
        """

    /// merge v3 model output with the code-parsed numbers into the v2 JSON shape
    public static func mergeV3(_ json: String, _ n: NumericRequest) -> String? {
        guard var o = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        o["minutes"] = n.minutes; o["songCount"] = n.songCount; o["minBPM"] = n.minBPM; o["maxBPM"] = n.maxBPM
        o["keys"] = n.keys
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
}
