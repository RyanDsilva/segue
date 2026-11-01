import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
import SQLite3
import Testing

/// Song pipeline integration suite (phase 1 spec, "Test strategy"): fixture songs loaded
/// through the real `LibraryStore` (temp-dir library, real files, real GRDB index), view
/// transforms applied through the same `RenderModel` the preview and live view draw from,
/// and "Apply transposition to source" saved, re-opened from disk and checked in the index.
struct EditingSongPipelineTests {
    // MARK: - View transforms

    @Test(arguments: goldens)
    func `rendered chords match golden expectations`(golden: Golden) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let record = try await store.createSong(source: EditingFixtures.load(golden.fixture))
        let options = DisplayOptions(
            transpose: golden.transpose,
            capoMode: golden.capoMode,
            nashville: golden.nashville,
            showDiagrams: false,
        )
        let model = RenderModel(document: record.document, options: options)
        #expect(Self.uniqueTexts(model) == golden.chords)
        #expect(model.header.key == golden.headerKey)
    }

    static let transposeRange = Array(-12 ... 12)

    @Test(arguments: EditingFixtures.names)
    func `every view transform keeps lyrics and shifts every chord correctly`(
        name: String,
    ) async throws {
        let lib = try TestLibrary()
        let store = try await lib.openStore()
        let record = try await store.createSong(source: EditingFixtures.load(name))
        let reloaded = try #require(try await lib.openStore().song(id: record.id))
        let document = reloaded.document
        let capo = max(document.metadata.capo ?? 0, 0)

        var nashvilleTexts: [String]?
        for transpose in Self.transposeRange {
            for capoMode in CapoMode.allCases {
                let options = DisplayOptions(
                    transpose: transpose,
                    capoMode: capoMode,
                    showDiagrams: false,
                )
                let model = RenderModel(document: document, options: options)
                let shift = transpose + (capoMode == .concert ? capo : 0)
                #expect(model.transform.semitones == shift)
                Self.expectLyricsUnchanged(model, document: document)
                for chord in Self.renderChords(model) {
                    try Self.expectShifted(chord, by: shift, displayKey: model.transform.displayKey)
                }

                let nashville = RenderModel(
                    document: document,
                    options: DisplayOptions(
                        transpose: transpose,
                        capoMode: capoMode,
                        nashville: true,
                        showDiagrams: false,
                    ),
                )
                let texts = Self.renderChords(nashville).map(\.text)
                if let nashvilleTexts {
                    #expect(texts == nashvilleTexts, "Nashville must be transposition-invariant")
                }
                nashvilleTexts = texts
            }
        }
    }

    @Test(arguments: EditingFixtures.wellFormed)
    func `diagram strip resolves a shape for every chord`(name: String) throws {
        let document = try ChordProParser.parse(EditingFixtures.load(name)).0
        for instrument in Instrument.allCases {
            for capoMode in CapoMode.allCases {
                let model = RenderModel(
                    document: document,
                    options: DisplayOptions(
                        capoMode: capoMode,
                        nashville: true,
                        showDiagrams: true,
                        instrument: instrument,
                    ),
                )
                let letters = RenderModel(
                    document: document,
                    options: DisplayOptions(capoMode: capoMode, showDiagrams: false),
                )
                let expectedNames = Self.uniqueTexts(letters).filter { text in
                    if case .chord = ChordToken(parsing: text) {
                        return true
                    }
                    return false
                }
                #expect(model.diagrams.map(\.name) == expectedNames)
                for diagram in model.diagrams {
                    switch instrument {
                    case .guitar:
                        #expect(diagram.guitar != nil, "no guitar shape for \(diagram.name)")
                        #expect(diagram.piano == nil)
                        let capo = document.metadata.capo.flatMap { $0 > 0 ? $0 : nil }
                        #expect(diagram.capoFret == (capoMode == .shapes ? capo : nil))
                    case .piano:
                        #expect(diagram.piano != nil, "no piano voicing for \(diagram.concertName)")
                        #expect(diagram.guitar == nil)
                    }
                }
            }
        }
        let hidden = RenderModel(document: document, options: DisplayOptions(showDiagrams: false))
        #expect(hidden.diagrams.isEmpty)
    }

    @Test
    func `piano diagrams are always concert pitch and song defines win`() throws {
        let document = try ChordProParser.parse(EditingFixtures.load(Self.defines)).0
        let piano = RenderModel(
            document: document,
            options: DisplayOptions(showDiagrams: true, instrument: .piano),
        )
        #expect(piano.diagrams.first?.name == "G")
        #expect(piano.diagrams.first?.concertName == "A")
        #expect(piano.diagrams.first?.piano?.root == PitchClass(9))

        let guitar = RenderModel(document: document, options: DisplayOptions(showDiagrams: true))
        let gadd9 = try #require(guitar.diagrams.first { $0.name == "Gadd9" })
        #expect(gadd9.guitar?.source == .songDefine)
        #expect(gadd9.guitar?.shape.frets == [3, 2, 0, 2, 0, 3])
        #expect(gadd9.capoFret == 2)

        // Transposed away from the defined name, the define no longer applies.
        let moved = RenderModel(
            document: document,
            options: DisplayOptions(transpose: 2, showDiagrams: true),
        )
        #expect(moved.diagrams.first { $0.name == "Aadd9" }?.guitar?.source != .songDefine)
    }

    @Test
    func `meta tuning wins over the sidecar tuning`() throws {
        let document = try ChordProParser.parse(EditingFixtures.load("unknown-directives.cho")).0
        let model = RenderModel(document: document, options: DisplayOptions(tuning: .openG))
        #expect(model.tuning.strings == Tuning.dadgad.strings)
        let plain = try ChordProParser.parse(EditingFixtures.load(Self.basic)).0
        #expect(RenderModel(document: plain, options: DisplayOptions(tuning: .openG))
            .tuning == .openG)
    }

    @Test
    func `render sections keep comments, stanza breaks, repeats and verbatim tabs`() throws {
        let document = try ChordProParser.parse(EditingFixtures.load("generic-sections.cho")).0
        let model = RenderModel(document: document, options: DisplayOptions(showDiagrams: false))
        let tab = try #require(model.sections.first { $0.kind == .tab })
        #expect(!tab.isEditable)
        #expect(tab.label == "Riff")
        #expect(tab.items.first == .verbatim(
            text: "e|-----0---0-------|",
            path: BlockPath(block: tab.path?.block ?? -1, item: 0),
        ))
        #expect(model.sections.map(\.id) == Array(model.sections.indices))

        let basic = try ChordProParser.parse(EditingFixtures.load(Self.basic)).0
        let rendered = RenderModel(document: basic, options: DisplayOptions(showDiagrams: false))
        #expect(rendered.sections.map(\.label) == basic.displaySections.map(\.label))
        #expect(rendered.sections.map(\.isRepeat) == basic.displaySections.map(\.isRepeat))
        #expect(rendered.header.title == "Lanterns on the Water")
        #expect(rendered.header.capo == 2)
        #expect(rendered.header.keyStatus == .declared)

        let comments = try ChordProParser.parse(EditingFixtures.load("comments-both-kinds.cho")).0
        let commented = RenderModel(
            document: comments,
            options: DisplayOptions(showDiagrams: false),
        )
        let commentTexts = commented.sections.flatMap(\.items).compactMap { item -> String? in
            if case let .comment(text, _, _) = item {
                return text
            }
            return nil
        }
        #expect(!commentTexts.isEmpty)
    }

    @Test
    func `songs without a key show an inferred key and transform by it`() throws {
        let document = try ChordProParser.parse(EditingFixtures.load("editing-no-key.cho")).0
        let context = KeyContext(document: document)
        #expect(context.declared == nil)
        #expect(context.writtenKey?.name == "C")
        #expect(context.status == .inferred)
        let model = RenderModel(document: document, options: DisplayOptions(transpose: 2))
        #expect(model.header.keyStatus == .inferred)
        #expect(model.header.key == "D")
        #expect(Self.uniqueTexts(model) == ["D", "Bm", "G", "A"])
        #expect(RenderModel(document: SongDocument(), options: DisplayOptions()).header.keyStatus
            == .unknown)
    }

    @Test
    func `chord input in the display key maps back to source spelling`() throws {
        let document = try ChordProParser.parse(EditingFixtures.load(Self.basic)).0
        let concert = DisplayTransform(
            options: DisplayOptions(transpose: 3, capoMode: .concert),
            key: KeyContext(document: document),
            capo: 2,
        )
        // Written G, displayed up 5 semitones in C: typing F in the display means C.
        #expect(concert.displayKey?.name == "C")
        #expect(concert.sourceChord(fromDisplayed: "F") == "C")
        #expect(concert.sourceChord(fromDisplayed: "Dm7/A") == "Am7/E")
        #expect(concert.sourceChord(fromDisplayed: "blah") == "blah")
        let identity = DisplayTransform(
            options: DisplayOptions(nashville: true),
            key: KeyContext(document: document),
            capo: 2,
        )
        #expect(identity.sourceChord(fromDisplayed: "F#m") == "F#m")
        for chord in ["C", "Am7", "F/A", "G7sus4", "Bbmaj7"] {
            let typed = concert
                .display(ChordToken(parsing: concert.sourceChord(fromDisplayed: chord)))
            #expect(typed == chord)
        }
    }

    // MARK: - Helpers

    static func renderChords(_ model: RenderModel) -> [RenderChord] {
        model.sections.flatMap(\.items).flatMap { item -> [RenderChord] in
            if case let .lyrics(line) = item {
                return line.chords
            }
            return []
        }
    }

    static func uniqueTexts(_ model: RenderModel) -> [String] {
        var seen = Set<String>()
        return renderChords(model).map(\.text).filter { seen.insert($0).inserted }
    }

    static func expectLyricsUnchanged(_ model: RenderModel, document: SongDocument) {
        let rendered = model.sections.flatMap(\.items).compactMap { item -> String? in
            if case let .lyrics(line) = item {
                return line.lyrics
            }
            return nil
        }
        let lines = Set(document.plainLyrics.components(separatedBy: "\n"))
        for lyric in rendered {
            #expect(lines.contains(lyric))
        }
    }

    /// A displayed chord is the written chord moved by `shift` semitones, spelled by the
    /// key signature of `displayKey`; unknown and N.C. tokens stay verbatim.
    static func expectShifted(_ chord: RenderChord, by shift: Int, displayKey: SongKey?) throws {
        let written = ChordToken(parsing: chord.original)
        guard case let .chord(source) = written else {
            #expect(chord.text == chord.original)
            return
        }
        let shown = try #require(ChordToken(parsing: chord.text).chord, "\(chord.text)")
        #expect(shown.symbol.root.pitchClass == source.symbol.root.pitchClass.transposed(by: shift))
        #expect(
            shown.symbol.bass?.pitchClass
                == source.symbol.bass?.pitchClass.transposed(by: shift),
        )
        #expect(shown.symbol.suffix == source.symbol.suffix)
        if PitchClass(shift).rawValue == 0 {
            #expect(chord.text == chord.original)
        }
        guard PitchClass(shift).rawValue != 0, let displayKey else { return }
        let major = displayKey.relativeMajor.name
        let names = [shown.symbol.root] + (shown.symbol.bass.map { [$0] } ?? [])
        for note in names {
            let spelled = KeySpelling.spell(note.pitchClass, in: displayKey)
            #expect(note == spelled, "\(chord.text) in \(major)")
        }
    }

    /// The `key` column of the song's row in the index (the state directory's `index.sqlite`), read
    /// with plain SQLite.
    static func indexedKey(_ lib: TestLibrary, id: SongID) throws -> String? {
        var db: OpaquePointer?
        let path = lib.state.indexDatabase.path(percentEncoded: false)
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT key FROM songs WHERE id = ?", -1, &statement, nil)
            == SQLITE_OK
        else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(
            statement,
            1,
            id.description,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self),
        )
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0)
        else { return nil }
        return String(cString: text)
    }
}
