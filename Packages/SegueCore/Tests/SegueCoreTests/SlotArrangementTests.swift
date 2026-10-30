import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import Setlists
import Shows
import Support
import Testing

/// Per-slot arrangements (P3-16, P8-2, R122, R123, R149): passes with show modes, the setlist
/// file at schema 6 and the show record at 4 (with their migrations), resolution against the
/// song as it is now, pass names, the stage's arranged plan, and timing.
struct SlotArrangementTests {
    /// Intro, Verse 1, Chorus, Verse 2, a `{chorus}` repeat, Bridge, a `{chorus}` repeat, then
    /// a loose comment after the last chorus.
    static let song = """
    {title: Arranged}
    {duration: 4:00}

    {start_of_intro: Intro}
    [G] [C] [D]
    {end_of_intro}

    {start_of_verse: Verse 1}
    [G]First verse line one
    [C]First verse line two
    {end_of_verse}

    {start_of_chorus}
    [D]Chorus line one
    [G]Chorus line two
    {end_of_chorus}

    {start_of_verse: Verse 2}
    [G]Second verse line one
    [C]Second verse line two
    {end_of_verse}

    {chorus}

    {start_of_bridge}
    [Em]Bridge line one
    {end_of_bridge}

    {chorus}

    {comment: Let it ring}
    """

    static func units(_ source: String = song) -> [SongSectionUnit] {
        SongSections.units(of: ChordProParser.parse(source).0)
    }

    static func pass(
        _ units: [SongSectionUnit],
        _ name: String,
        _ mode: PassMode = .full,
    ) -> ArrangementPass {
        guard let unit = units.first(where: { $0.name == name }) else {
            Issue.record("no part named \(name)")
            return ArrangementPass(anchor: .loose(after: nil, block: 99))
        }
        return ArrangementPass(anchor: unit.anchor, fingerprint: unit.fingerprint, mode: mode)
    }

    // MARK: Song parts

    @Test
    func `every section and loose block is a part, with ordinals for repeated titles`() {
        let units = Self.units()
        #expect(units.map(\.name) == [
            "Intro", "Verse 1", "Chorus 1st", "Verse 2", "Chorus 2nd", "Bridge", "Chorus 3rd",
            "After Chorus",
        ])
        #expect(units[7].anchor == .loose(
            after: SectionRef(label: "Chorus", occurrence: 3),
            block: 1,
        ))
        #expect(units[4].fingerprint == "repeat")
        #expect(units[4].firstLine == "Chorus line one")
        // Lines before the first section are the lead-in.
        let leadIn = Self.units("[G]Hum along\n\n{start_of_verse}\nWords\n{end_of_verse}\n")
        #expect(leadIn.map(\.name) == ["Lead-in", "Verse"])
        #expect(leadIn[0].anchor == .loose(after: nil, block: 1))
    }

    // MARK: Resolution

    @Test
    func `a renamed, removed or shifted section makes it out of date`() {
        let units = Self.units()
        let arrangement = SlotArrangement.fullSong(units)
        let renamed = Self.song.replacingOccurrences(of: "Verse 2}", with: "Verse Two}")
        #expect(ArrangementResolver.resolve(arrangement, units: Self.units(renamed)).isOutOfDate)
        let removed = Self.song
            .replacingOccurrences(of: "{start_of_bridge}", with: "{start_of_verse: Verse 3}")
            .replacingOccurrences(of: "{end_of_bridge}", with: "{end_of_verse}")
        #expect(ArrangementResolver.resolve(arrangement, units: Self.units(removed)).isOutOfDate)
        // The labels and occurrences still exist, but the first verse's words moved: the
        // fingerprint catches it (R123).
        let shifted = Self.song
            .replacingOccurrences(of: "First verse line one", with: "Brand new opening")
        guard case let .outOfDate(missing) = ArrangementResolver.resolve(
            arrangement,
            units: Self.units(shifted),
        ) else {
            Issue.record("expected out of date")
            return
        }
        #expect(missing.map(\.anchor) == [.section(SectionRef(label: "Verse 1", occurrence: 1))])
        // Chords only (a re-voicing) do not count.
        let revoiced = Self.song.replacingOccurrences(of: "[G]First", with: "[Gmaj7]First")
        #expect(!ArrangementResolver.resolve(arrangement, units: Self.units(revoiced)).isOutOfDate)
    }

    // MARK: Stage

    @Test
    func `the stage lays out the arrangement with song-relative cues and repeats`() {
        let model = LiveLayoutSupport.model(source: Self.song)
        let units = Self.units()
        // The written chorus is skipped; the last `{chorus}` repeat plays twice.
        let arrangement = SlotArrangement(passes: [
            Self.pass(units, "Verse 1"),
            Self.pass(units, "Chorus 1st", .skip),
            Self.pass(units, "Chorus 3rd"),
            Self.pass(units, "Chorus 3rd"),
        ])
        guard case let .applied(order, _) = ArrangementResolver.resolve(arrangement, units: units)
        else {
            Issue.record("expected applied")
            return
        }
        let cue = SongCue(section: "Chorus", occurrence: 3, text: "Big finish")
        let collapsed = LayoutRequest(
            model: model,
            viewport: LiveLayoutSupport.macBook13,
            minLyricSize: 22,
            cues: [cue, SongCue(section: "Bridge", text: "Quiet")],
            arrangement: order,
        )
        let plan = LayoutEngine.plan(collapsed, metrics: FixedAdvanceMetrics())
        let blocks = plan.columns.flatMap(\.blocks).filter { $0.part == 0 }
        #expect(blocks.map(\.id) == [0, 1, 2])
        // The repeat whose chorus was skipped is written out in full; its second play
        // collapses ("Repeat chorus") with the song's collapse setting on.
        guard case .rows = blocks[1].content else {
            Issue.record("the first chorus play is in full")
            return
        }
        guard case .collapsed = blocks[2].content else {
            Issue.record("the second play collapses")
            return
        }
        // The cue stays on its song-relative chorus (first play only); the skipped bridge's
        // cue is not played and is not moved to the notes.
        #expect(blocks.flatMap(\.cues).map(\.text) == ["Big finish"])
        #expect(plan.blocks.allSatisfy { $0.id != -1 })

        var expanded = collapsed
        expanded.collapseRepeats = false
        let full = LayoutEngine.plan(expanded, metrics: FixedAdvanceMetrics())
        let fullBlocks = full.columns.flatMap(\.blocks).filter { $0.part == 0 }
        #expect(fullBlocks.allSatisfy {
            if case .rows = $0.content {
                return true
            }
            return false
        })
    }

    // MARK: Files

    @Test
    func `an arrangement persists at schema 6 and reloads`() async throws {
        let lib = try TestLibrary()
        let library = try await lib.openStore()
        let record = try await library.createSong(source: Self.song)
        let (store, _) = try await lib.loadSetlists()
        let created = try await store.create(name: "Friday")
        var setlist = try await store.insertSongs([record.id], into: created.id)
        let units = SongSections.units(of: record.document)
        var entry = setlist.entries[0]
        entry.arrangement = SlotArrangement(
            passes: [
                Self.pass(units, "Intro", .chordsOnly),
                Self.pass(units, "After Chorus"),
                Self.pass(units, "After Chorus"),
            ],
            knownParts: KnownPart.all(units),
            length: 155,
        )
        setlist = try await store.updateEntry(entry, in: setlist.id)

        let json = try lib.read("setlists/friday.setlist.json")
        #expect(json.contains("\"schemaVersion\" : 6"))
        #expect(json.contains("\"mode\" : \"chords\""))
        #expect(json.contains("\"knownParts\""))
        #expect(json.contains("\"section\" : \"Intro\""))
        #expect(json.contains("\"loose\" : 1"))
        #expect(json.contains("\"after\" : \"Chorus\""))
        #expect(json.contains("\"length\" : 155"))
        let (reloaded, issues) = try await lib.loadSetlists()
        #expect(issues.isEmpty)
        #expect(await reloaded.setlist(id: setlist.id) == setlist)

        // Reset to full song: the key disappears.
        entry.arrangement = nil
        _ = try await store.updateEntry(entry, in: setlist.id)
        #expect(try !lib.read("setlists/friday.setlist.json").contains("arrangement"))
    }

    @Test
    func `a v4 setlist reads unchanged and a v7 one opens read-only`() async throws {
        let lib = try TestLibrary()
        let song = SongID(ULID(milliseconds: 5, randomness: Array(repeating: 7, count: 10)))
        let item = SetlistItemID(ULID(milliseconds: 6, randomness: Array(repeating: 8, count: 10)))
        let setlistID = SetlistID(ULID(milliseconds: 4, randomness: Array(repeating: 9, count: 10)))
        let v4 = """
        {"schemaVersion": 4, "id": "\(setlistID)",
         "name": "Old", "entries": [{"itemId": "\(item)", "songId": "\(song)", "locked": true}]}
        """
        try lib.write(v4, to: "setlists/old.setlist.json")
        let otherID = SetlistID(ULID(milliseconds: 4, randomness: Array(repeating: 3, count: 10)))
        let v7 = """
        {"schemaVersion": 7, "id": "\(otherID)", "name": "Future",
         "entries": [{"itemId": "\(item)", "songId": "\(song)",
           "arrangement": {"passes": [{"section": "Verse", "occurrence": 1}]}}]}
        """
        try lib.write(v7, to: "setlists/future.setlist.json")

        let (store, issues) = try await lib.loadSetlists()

        #expect(issues.isEmpty)
        let old = try #require(await store.setlist(id: setlistID))
        #expect(old.readOnly == nil)
        #expect(old.entries == [SetlistEntry(itemId: item, songId: song, locked: true)])
        let future = try #require(await store.setlist(id: otherID))
        #expect(future.readOnly == .newerSchema(found: 7, supported: 6))
        #expect(future.entries[0].arrangement?.passes.count == 1)
        #expect(try lib.read("setlists/future.setlist.json") == v7)
    }

    @Test
    func `a show copies the arrangement at start and records what the stage did`() async throws {
        let harness = try await ShowHarness()
        var (setlist, _) = try await harness.makeSet(2)
        var entry = setlist.entries[0]
        let arrangement = SlotArrangement(
            passes: [ArrangementPass(anchor: .loose(after: nil, block: 1))],
            length: 90,
        )
        entry.arrangement = arrangement
        setlist = try await harness.setlists.updateEntry(entry, in: setlist.id)
        let show = try await ShowController.start(
            setlist: setlist,
            kind: .gig,
            environment: harness.environment(),
        )
        let item = setlist.entries[0].itemId
        let showItem = ShowItemID(item.ulid)

        // Edited mid-show: the running show keeps its start snapshot, as with key and capo.
        var edited = setlist.entries[0]
        edited.arrangement = nil
        edited.overrides.transpose = 2
        _ = try await harness.setlists.updateEntry(edited, in: setlist.id)
        let record = await show.state.record
        #expect(record.items[0].arrangement == arrangement)
        #expect(record.items[0].overrides.transpose == nil)
        #expect(record.items[1].arrangement == nil)

        try await show.recordArrangementState(.outOfDate, for: showItem)
        try await show.recordArrangementState(.applied, for: showItem)
        _ = try await show.perform(.next)
        let reloaded = try #require(try await harness.reloadedShow(record.id))
        #expect(reloaded.schemaVersion == 4)
        #expect(reloaded.items[0].arrangementState == .outOfDate)
        #expect(reloaded.items[0].arrangement == arrangement)
    }

    // MARK: Timing

    @Test
    func `an arranged slot counts its own length, never the song's`() {
        func ulid(_ time: UInt64, _ byte: Int) -> ULID {
            ULID(milliseconds: time, randomness: Array(repeating: UInt8(byte), count: 10))
        }
        let songs = (0 ..< 2).map { SongID(ulid(1, $0)) }
        let items = (0 ..< 2).map { SetlistItemID(ulid(2, $0)) }
        let lengths = Dictionary(uniqueKeysWithValues: songs.map {
            ($0, SongLength(seconds: 240, source: .directive))
        })
        var entries = zip(items, songs).map { SetlistEntry(itemId: $0, songId: $1) }
        entries[0].arrangement = SlotArrangement(passes: [], length: 150)
        var timing = SetlistTiming(entries: entries, lengths: lengths, target: nil)
        #expect(timing.items[0].length == SongLength(seconds: 150, source: .slot))
        #expect(timing.total == 390)
        // No slot length: unknown and flagged, even though the song has a `{duration}`.
        entries[0].arrangement?.length = nil
        timing = SetlistTiming(entries: entries, lengths: lengths, target: nil)
        #expect(timing.items[0].length == nil)
        #expect(timing.unknownItemIds == [items[0]])
        #expect(timing.total == 240)
    }
}
