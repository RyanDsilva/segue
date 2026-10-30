import Foundation
import MusicTheory
import Testing

/// Walk-ups (P8-4 sections 8.3, 8.13): the golden corpus, the legacy rows and the score
/// breakdown.
struct WalkUpTests {
    // MARK: Golden corpus

    struct Case: Decodable, CustomTestStringConvertible, Sendable {
        var name: String
        var from: String
        var to: String?
        var key: String?
        var genre: BassGenre?
        var beats: Int?
        var tempo: Double?
        var intoSection: Bool
        var energyUp: Bool?
        var prev: String?
        var next: String?
        var expectTop1: String?
        var expectContains: [String]?
        var expectNone: Bool?
        var mustNotContain: [String]?

        var testDescription: String {
            name
        }
    }

    static let corpus: [Case] = {
        guard let url = Bundle.module.url(
            forResource: "Fixtures/walkups/WalkUpCorpus",
            withExtension: "json",
        ), let data = try? Data(contentsOf: url) else { return [] }
        struct File: Decodable {
            var cases: [Case]
        }
        return (try? JSONDecoder().decode(File.self, from: data).cases) ?? []
    }()

    @Test
    func `the corpus has about sixty cases`() {
        #expect(Self.corpus.count >= 55)
    }

    @Test(arguments: corpus)
    func `golden corpus`(_ row: Case) throws {
        let shown = try Self.texts(row)
        if row.expectNone == true {
            #expect(shown.isEmpty, "\(shown)")
        }
        if let top = row.expectTop1 {
            #expect(shown.first == top, "\(shown)")
        }
        for wanted in row.expectContains ?? [] {
            #expect(shown.contains(wanted), "\(wanted) in \(shown)")
        }
        for unwanted in row.mustNotContain ?? [] {
            #expect(!shown.contains(unwanted), "\(unwanted) in \(shown)")
        }
    }

    /// The ranked candidates as text ("A B", "hold"). A target that is not a chord (N.C.,
    /// none) has nothing to walk into.
    static func texts(_ row: Case) throws -> [String] {
        let key = row.key.flatMap(SongKey.init(parsing:))
        guard let to = row.to, let arriving = ChordSymbol(parsing: to) else {
            return try chain(row)
        }
        let departing = try #require(ChordSymbol(parsing: row.from))
        let context = try WalkUpContext(
            key: key,
            departing: departing,
            arriving: arriving,
            genre: row.genre,
            beats: row.beats,
            tempo: row.tempo,
            intoSection: row.intoSection,
            energyUp: row.energyUp,
            writtenLine: WalkUp.isWrittenLine(
                previous: row.prev.flatMap(bass),
                from: #require(bass(row.from)),
                to: #require(bass(to)),
                next: row.next.flatMap(bass),
            ),
        )
        return try WalkUp.candidates(
            from: #require(bass(row.from)),
            to: #require(bass(to)),
            context: context,
        ).map(text)
    }

    /// No chord to walk into (`N.C.`, or A is the last chord): rule S3, nothing.
    static func chain(_: Case) throws -> [String] {
        []
    }

    static func bass(_ chord: String) -> PitchClass? {
        ChordSymbol(parsing: chord).map { ($0.bass ?? $0.root).pitchClass }
    }

    static func text(_ candidate: WalkUpCandidate) -> String {
        candidate.kind == .hold ? "hold" : candidate.notes.map(\.chartName).joined(separator: " ")
    }

    // MARK: Legacy rows (the pre-research rule, `WalkUp.notes`)

    @Test(arguments: [
        ("G", "C", "G", "A B"), ("C", "G", "G", "B A"), ("G", "D", "G", "F# E"),
        ("G", "Em", "G", "F#"), ("C", "D", "G", "C#"), ("D", "C", "G", "Db"),
        ("G", "G7", "G", ""), ("G", "A", "G", "G#"), ("E", "F", "C", ""), ("C", "F#", "C", "F"),
        ("Bb", "Eb", "C", "C D"), ("Bb", "C", "C", "B"), ("G", "C", "-", "B"),
    ])
    func `legacy rule`(from: String, to: String, key: String, expected: String) throws {
        let notes = try WalkUp.notes(
            from: #require(Self.bass(from)),
            to: #require(Self.bass(to)),
            key: SongKey(parsing: key),
        )
        #expect(notes.map(\.chartName).joined(separator: " ") == expected)
    }

    @Test
    func `documented changes from the legacy rule`() throws {
        func top(
            _ from: String,
            _ to: String,
            _ key: String,
            _ genre: BassGenre?,
        ) throws -> String {
            let row = Case(
                name: "", from: from, to: to, key: key, genre: genre, intoSection: false,
            )
            return try Self.texts(row).first ?? ""
        }
        #expect(try top("E", "Am", "Am", nil) == "F# G#") // was "F G"
        #expect(try top("E", "Am", "Am", .bollywood) == "F G#")
        #expect(try top("A7", "Dm", "C", nil) == "B C#")
        let line = Case(
            name: "", from: "F", to: "G", key: "Am", genre: nil, intoSection: false, next: "Am",
        )
        #expect(try Self.texts(line) == ["hold", "F#"])
    }

    // MARK: Breakdown

    @Test
    func `the breakdown lists every term and sums to the score`() throws {
        let context = try WalkUpContext(
            key: SongKey(parsing: "G"),
            departing: #require(ChordSymbol(parsing: "G")),
            arriving: #require(ChordSymbol(parsing: "C")),
            genre: .pop,
        )
        let candidates = WalkUp.candidates(from: PitchClass(7), to: PitchClass(0), context: context)
        let walk = try #require(candidates.first)
        #expect(Self.text(walk) == "A B")
        #expect(walk.kind == .scaleWalk)
        #expect(walk.breakdown[.genrePrior] == 3)
        #expect(walk.breakdown[.resolution] == 2)
        #expect(walk.breakdown[.direction] == WalkUpWeights.standard.directionShortest)
        #expect(walk.breakdown.values.reduce(0, +) == walk.score)
        #expect(walk.offsets == [-3, -1])
        #expect(walk.degrees == ["2", "3"])
        #expect(walk.chromatic == [false, false])
        #expect(walk.direction == .up)
    }

    @Test
    func `a chromatic note is flagged and spelled by direction`() throws {
        let up = try WalkUpContext(
            key: SongKey(parsing: "G"),
            departing: #require(ChordSymbol(parsing: "C")),
            arriving: #require(ChordSymbol(parsing: "D")),
        )
        let note = try #require(WalkUp.candidates(
            from: PitchClass(0),
            to: PitchClass(2),
            context: up,
        )
        .first)
        #expect(note.notes.map(\.chartName) == ["C#"])
        #expect(note.chromatic == [true])
        #expect(note.degrees == ["#4"])
        let down = try WalkUpContext(
            key: SongKey(parsing: "G"),
            departing: #require(ChordSymbol(parsing: "D")),
            arriving: #require(ChordSymbol(parsing: "C")),
        )
        let flat = try #require(WalkUp.candidates(
            from: PitchClass(2),
            to: PitchClass(0),
            context: down,
        )
        .first)
        #expect(flat.notes.map(\.chartName) == ["Db"])
        #expect(flat.direction == .down)
    }

    @Test
    func `a saved pick is rebuilt from its offsets at any pitch`() throws {
        let context = try WalkUpContext(
            key: SongKey(parsing: "A"),
            departing: #require(ChordSymbol(parsing: "A")),
            arriving: #require(ChordSymbol(parsing: "D")),
        )
        let pick = try #require(WalkUp.candidate(
            kind: .scaleWalk,
            offsets: [-3, -1],
            from: PitchClass(9),
            to: PitchClass(2),
            context: context,
        ))
        #expect(pick.notes.map(\.chartName) == ["B", "C#"])
        #expect(WalkUp.candidate(
            kind: .scaleWalk,
            offsets: [12],
            from: PitchClass(9),
            to: PitchClass(2),
            context: context,
        ) == nil)
    }
}
