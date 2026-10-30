import ChordPro
import Editing
import Library
import MusicTheory
import Testing

/// Walk-ups applied to a song (P8-4 sections 8.6, 8.11), through real render models.
struct BassLineTests {
    static let song = """
    {key: G}
    {start_of_verse}
    [G]Hello there [C]my friend [D]and so
    {end_of_verse}
    {start_of_chorus}
    [G]Sing it [Em]loud
    {end_of_chorus}

    """

    static func model(
        _ source: String,
        density: WalkUpDensity = .everyChange,
        nashville: Bool = false,
        transpose: Int = 0,
        notes: Bool = true,
    ) -> (RenderModel, SongDocument) {
        let (document, _) = ChordProParser.parse(source)
        let options = DisplayOptions(transpose: transpose, nashville: nashville)
            .withBass(InstrumentProfile(bassNotes: notes, walkUps: density))
        return (RenderModel(document: document, options: options), document)
    }

    /// The approach runs drawn, in order, as "chord: notes".
    static func runs(_ model: RenderModel) -> [String] {
        model.sections.flatMap(\.items).flatMap { item -> [String] in
            guard case let .lyrics(line) = item else { return [] }
            return line.chords.compactMap { chord in
                chord.approach.map { "\(chord.original): \($0.notes.joined(separator: " "))" }
            }
        }
    }

    @Test
    func `every change shows its top candidate`() {
        let (model, document) = Self.model(Self.song)
        let runs = Self.runs(BassLine.annotated(model, document: document, prefs: BassPrefs()))
        #expect(runs == ["G: A B", "C: C#", "D: E F#", "G: F#"])
    }

    @Test
    func `into sections shows only the section-final change`() {
        let (model, document) = Self.model(Self.song, density: .sections)
        let runs = Self.runs(BassLine.annotated(model, document: document, prefs: BassPrefs()))
        #expect(runs == ["D: E F#"])
    }

    @Test
    func `off, or without the bass-note view, nothing is drawn`() {
        for (model, document) in [
            Self.model(Self.song, density: .off),
            Self.model(Self.song, notes: false),
        ] {
            #expect(BassLine.annotated(model, document: document, prefs: BassPrefs()) == model)
        }
    }

    @Test
    func `the last chord and N.C. get nothing`() {
        let (model, document) = Self.model("{key: G}\n[G]One [N.C.]two [C]three\n")
        #expect(Self.runs(BassLine.annotated(model, document: document, prefs: BassPrefs()))
            .isEmpty)
    }

    @Test
    func `a chorus stub leads into its chorus`() {
        let source = """
        {key: G}
        {start_of_chorus}
        [C]Sing [D]it
        {end_of_chorus}
        {start_of_verse}
        [G]Hello
        {end_of_verse}
        {chorus}

        """
        let (model, document) = Self.model(source)
        let changes = BassLine.changes(model, document: document, prefs: BassPrefs())
        let last = changes.last
        #expect(last?.fromName == "G")
        #expect(last?.toName == "C")
        #expect(last?.intoSection == true)
    }

    @Test
    func `the song's Nashville toggle draws degrees`() {
        let (model, document) = Self.model(Self.song, nashville: true)
        let runs = Self.runs(BassLine.annotated(model, document: document, prefs: BassPrefs()))
        #expect(runs.first == "G: 2 3")
    }

    @Test
    func `the song's feel overrides the profile's`() {
        let (model, document) = Self.model(Self.song)
        let rock = BassLine.changes(model, document: document, prefs: BassPrefs(genre: .rock))
        #expect(rock.first?.shown?.notes.map(\.chartName) == ["B"])
    }

    /// A pick for the first change (G into C), saved through the anchor helpers.
    static func pick(_ kind: WalkUpKind, offsets: [Int], model: RenderModel, document: SongDocument)
        -> WalkUpPick?
    {
        let changes = BassLine.changes(model, document: document, prefs: BassPrefs())
        guard let change = changes.first,
              let anchor = ChordAnchors.anchor(
                  at: change.id.from,
                  units: SongSections.units(of: document),
                  sections: model.sections,
              )
        else { return nil }
        return WalkUpPick(anchor: anchor, to: change.toBass, kind: kind, offsets: offsets)
    }

    @Test
    func `a pick shows, even where the density skips, and survives a transpose`() throws {
        let (model, document) = Self.model(Self.song, density: .sections)
        let pick = try #require(Self.pick(
            .chromBelow,
            offsets: [-1],
            model: model,
            document: document,
        ))
        let prefs = BassPrefs(walkUps: [pick])
        let runs = Self.runs(BassLine.annotated(model, document: document, prefs: prefs))
        #expect(runs == ["G: B", "D: E F#"])
        let (up, upDocument) = Self.model(Self.song, density: .sections, transpose: 2)
        let moved = Self.runs(BassLine.annotated(up, document: upDocument, prefs: prefs))
        #expect(moved.first == "G: C#")
    }

    @Test
    func `a hold pick shows nothing`() throws {
        let (model, document) = Self.model(Self.song)
        let pick = try #require(Self.pick(.hold, offsets: [], model: model, document: document))
        let runs = Self.runs(BassLine.annotated(
            model,
            document: document,
            prefs: BassPrefs(walkUps: [pick]),
        ))
        #expect(runs.first?.hasPrefix("C:") == true)
    }

    @Test
    func `an arranged order changes the target and an unmatched pick falls back`() throws {
        let (model, document) = Self.model(Self.song)
        let pick = try #require(Self.pick(
            .chromBelow,
            offsets: [-1],
            model: model,
            document: document,
        ))
        let resolved = ChordAnchors.resolve(
            [pick],
            units: SongSections.units(of: document),
            sections: model.sections,
        )
        #expect(resolved.unmatched.isEmpty)
        // Chorus first, then the verse: the verse's last chord leads nowhere.
        let order = [model.sections[1], model.sections[0]]
        let context = try #require(BassLine.context(
            for: model,
            document: document,
            prefs: BassPrefs(walkUps: [pick]),
        ))
        let changes = BassLine.changes(order, origins: [1, 0], context: context)
        #expect(changes.map(\.fromName) == ["G", "Em", "G", "C"])
        // Em (chorus end) into G (verse start): the arranged target.
        #expect(changes[1].toName == "G")
        #expect(changes[2].pick != nil)
    }

    // MARK: Anchors

    @Test
    func `anchors re-anchor and go unmatched as the spec rows say`() throws {
        let (model, document) = Self.model(Self.song)
        let pick = try #require(Self.pick(
            .scaleWalk,
            offsets: [-3, -1],
            model: model,
            document: document,
        ))
        func resolves(_ source: String) -> Bool {
            let (edited, editedDocument) = Self.model(source)
            return ChordAnchors.resolve(
                [pick],
                units: SongSections.units(of: editedDocument),
                sections: edited.sections,
            ).unmatched.isEmpty
        }
        #expect(resolves(Self.song))
        // G changed to G7 keeps it.
        #expect(resolves(Self.song.replacingOccurrences(of: "[G]Hello", with: "[G7]Hello")))
        // A chord inserted before A: re-anchored within the section.
        #expect(resolves(Self.song.replacingOccurrences(of: "[G]Hello", with: "[D]He[G]llo")))
        // A same-label section inserted before it: the occurrence shifts, fp unique.
        #expect(resolves(Self.song.replacingOccurrences(
            of: "{start_of_verse}",
            with: "{start_of_verse}\n[A]Other words\n{end_of_verse}\n{start_of_verse}",
        )))
        // The target bass changed: unmatched.
        #expect(!resolves(Self.song.replacingOccurrences(of: "[C]my", with: "[Am]my")))
        // A's chord deleted: unmatched.
        #expect(!resolves(Self.song.replacingOccurrences(of: "[G]Hello", with: "Hello")))
    }

    @Test
    func `an unmatched pick is listed with its section, chords and notes as saved`() throws {
        let (model, document) = Self.model(Self.song)
        let pick = try #require(Self.pick(
            .scaleWalk,
            offsets: [-3, -1],
            model: model,
            document: document,
        ))
        let prefs = BassPrefs(walkUps: [pick])
        #expect(BassLine.unmatched(model, document: document, prefs: prefs).isEmpty)
        let (edited, editedDocument) = Self.model(
            Self.song.replacingOccurrences(of: "[C]my", with: "[Am]my"),
        )
        let unmatched = BassLine.unmatched(edited, document: editedDocument, prefs: prefs)
        #expect(unmatched == [pick])
        #expect(pick.savedSummary(key: SongKey(parsing: "G")) == "Verse: G \u{2192} C, A B")
        let hold = WalkUpPick(anchor: pick.anchor, to: "C", kind: .hold, offsets: [])
        #expect(hold.savedNotes(key: nil) == "Nothing")
    }
}
