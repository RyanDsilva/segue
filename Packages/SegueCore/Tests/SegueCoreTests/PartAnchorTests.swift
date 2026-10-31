import ChordPro
import Editing
import Library
import MusicTheory
import Testing

/// Parts anchor to their start and landing chords and apply per "Shows on" (P8-7 9.3).
struct PartAnchorTests {
    /// D (verse) into G (chorus): crosses a section boundary.
    static func intoChorus(_ fixture: PartFixture) throws -> Part {
        try fixture.part(from: (0, 2), to: (1, 0), bass: ["D", "G"])
    }

    @Test
    func `an unchanged song resolves the part`() throws {
        let fixture = PartFixture()
        let resolved = try fixture.resolved([Self.intoChorus(fixture)])
        #expect(resolved.unmatched.isEmpty)
        #expect(resolved.applied.first?.positions == [
            ChordPosition(section: 0, chord: 2), ChordPosition(section: 1, chord: 0),
        ])
    }

    @Test
    func `the part survives transpose and an edit below the first two lines`() throws {
        let part = try Self.intoChorus(PartFixture())
        let transposed = PartFixture(options: DisplayOptions(transpose: 3))
        #expect(transposed.resolved([part]).applied.count == 1)
        let edited = PartFixture(PartFixture
            .song + "\n{start_of_bridge}\n[Am]new [C]line\n{end_of_bridge}\n")
        #expect(edited.resolved([part]).applied.count == 1)
    }

    @Test
    func `a moved start chord re-anchors as picks do`() throws {
        let song = """
        {key: G}
        {start_of_verse}
        [G]Hello [C]there
        [G]la la
        [Em]la [D]friend
        {end_of_verse}
        {start_of_chorus}
        [G]Sing
        {end_of_chorus}

        """
        let fixture = PartFixture(song)
        let part = try fixture.part(from: (0, 4), to: (1, 0), bass: ["D", "G"])
        // A chord added before D below the first two lines: D is now chord 5, still the
        // only D.
        let moved = PartFixture(song.replacingOccurrences(
            of: "[Em]la [D]",
            with: "[Em]la [Am]oh [D]",
        ))
        let applied = try #require(moved.resolved([part]).applied.first)
        #expect(applied.positions.first == ChordPosition(section: 0, chord: 5))
    }

    @Test(arguments: [
        ("[D]friend", "[A]friend"),
        ("[D]friend", "[D]friend [A]too"),
        ("[G]Sing [Em]it", "Sing [Em]it"),
    ])
    func `a changed bass, an inserted chord or a deleted landing leaves it unmatched`(
        from: String,
        to: String,
    ) throws {
        let part = try Self.intoChorus(PartFixture())
        let changed = PartFixture(PartFixture.song.replacingOccurrences(of: from, with: to))
        let resolved = changed.resolved([part])
        #expect(resolved.applied.isEmpty)
        #expect(resolved.unmatched == [part])
    }

    @Test(arguments: [
        (PassFilter.all, [1, 2]), (.only([2]), [2]), (.only([1]), [1]), (.last, [2]),
    ])
    func `shows on filters the plays of the section`(filter: PassFilter, plays: [Int]) throws {
        // Inside the chorus (C into D), played twice: the chorus and its `{chorus}` stub.
        let fixture = PartFixture()
        let part = try fixture.part(from: (1, 2), to: (1, 3), bass: ["C", "D"], passes: filter)
        let found = fixture.resolved([part]).plays(in: fixture.timeline)
        #expect(found.map { fixture.timeline.chords[$0.chords.lowerBound].occurrence } == plays)
    }

    @Test
    func `in a played order the part applies only where the landing follows as written`() throws {
        let written = PartFixture()
        let part = try Self.intoChorus(written)
        let resolved = written.resolved([part])
        // Verse, verse, chorus: only the second verse leads into the chorus.
        let order = [PlayedPass(index: 0), PlayedPass(index: 0), PlayedPass(index: 1)]
        let played = PartFixture(order: order)
        let plays = resolved.plays(in: played.timeline)
        #expect(plays.count == 1)
        #expect(plays.first.map { played.timeline.chords[$0.chords.lowerBound].occurrence } == 2)
        // Verse then the bridge-less end: no chorus, no play.
        let none = PartFixture(order: [PlayedPass(index: 0)])
        #expect(resolved.plays(in: none.timeline).isEmpty)
    }

    @Test
    func `parts may not share a chord change`() throws {
        let fixture = PartFixture()
        let first = try Self.intoChorus(fixture)
        let resolved = fixture.resolved([first])
        let overlapping = [
            ChordPosition(section: 0, chord: 1),
            ChordPosition(section: 0, chord: 2),
            ChordPosition(section: 1, chord: 0),
        ]
        #expect(resolved.overlapping(overlapping) == [first])
        let apart = [ChordPosition(section: 1, chord: 0), ChordPosition(section: 1, chord: 1)]
        #expect(resolved.overlapping(apart).isEmpty)
        // A second saved part over the same change (a hand-edited file) is unmatched.
        let twice = try fixture.resolved([
            first,
            fixture.part(from: (0, 1), to: (1, 0), bass: ["C", "D", "G"]),
        ])
        #expect(twice.applied.count == 1)
        #expect(twice.unmatched.count == 1)
    }

    @Test
    func `a fill covers each change of its span for the plays it applies to`() throws {
        let fixture = PartFixture()
        let part = try fixture.part(from: (1, 2), to: (1, 3), bass: ["C", "D"], passes: .last)
        let resolved = fixture.resolved([part])
        let from = ChordPosition(section: 1, chord: 2)
        let to = ChordPosition(section: 1, chord: 3)
        #expect(resolved.covering(from: from, to: to, occurrence: 2, plays: 2) == part.id)
        #expect(resolved.covering(from: from, to: to, occurrence: 1, plays: 2) == nil)
        #expect(resolved.covering(from: to, to: from, occurrence: 2, plays: 2) == nil)
    }
}
