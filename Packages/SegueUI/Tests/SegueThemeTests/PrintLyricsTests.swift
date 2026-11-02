import ChordPro
import Editing
import Foundation
import Library
import LiveLayout
import PDFKit
import Printing
@testable import SegueUI
import Setlists
import Support
import Testing

/// The Lyrics part (P9-1 spec section 8, 14.3; P9-2 section 8): P9-2's singer view printed
/// through the stage's request path, read back with PDFKit: every lyric word, no chord, the
/// sounding key with no capo, Chords only passes as first lines tagged CHORDS, instrumental
/// parts named, song and slot notes never, cues only with the option.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PrintLyricsTests {
    typealias Support = PDFTestSupport

    static let folder = Support.screenshotRoot.appending(path: "p9-1c", directoryHint: .isDirectory)

    /// P9-2's fixture (an instrumental intro, a chorus comment, romanized Hindi) with an
    /// unlabelled chord-only lead-in, which a printed sheet leaves out (P9-2 5.2 rule 7).
    static let kitaabon = StageWindowSuites.SingerViewSnapshotTests.kitaabon
        .replacingOccurrences(of: "{tempo: 84}\n", with: "{tempo: 84}\n[Am] [G] [F] [E]\n")

    static let chordNames: Set = ["Am", "G", "F", "E", "C", "Dm", "D", "Em", "Bm"]

    /// Every word of the lyric lines, chords removed, as singer view keeps them.
    static func lyricWords(_ source: String) -> [String] {
        source.split(separator: "\n").filter { !$0.hasPrefix("{") }.flatMap { line in
            line.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                .split(whereSeparator: { $0.isWhitespace || ",.".contains($0) })
                .map(String.init)
        }
    }

    /// The tokens of extracted page text.
    static func tokens(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0.isWhitespace || ",.·()".contains($0) })
            .map(String.init))
    }

    /// Intro, Verse 1, Chorus, Verse 2, Chorus 2 Chords only, Bridge, Chorus 3.
    static func arranged(_ record: SongRecord) -> SlotArrangement {
        // swiftlint:disable:next large_tuple
        let passes: [(String, Int, PassMode)] = [
            ("Intro", 1, .full), ("Verse 1", 1, .full), ("Chorus", 1, .full),
            ("Verse 2", 1, .full), ("Chorus", 2, .chordsOnly), ("Bridge", 1, .full),
            ("Chorus", 3, .full),
        ]
        return SlotArrangement(passes: passes.map { label, occurrence, mode in
            ArrangementPass(
                anchor: .section(SectionRef(label: label, occurrence: occurrence)),
                mode: mode,
            )
        })
    }

    @Test
    func `a lyric sheet prints every lyric word and no chord`() async throws {
        var record = Support.record(Self.kitaabon, index: 4)
        record.sidecar.notes = "Count in four"
        record.sidecar.cues = [SongCue(section: "Bridge", text: "Softly")]
        let entry = SetlistEntry(
            itemId: Support.item(0),
            songId: record.id,
            note: "Watch Ravi",
            arrangement: Self.arranged(record),
        )
        let setlist = Setlist(id: Support.setlistID(), name: "Friday Set", entries: [entry])
        let snapshot = Support.snapshot(.slot(PDFSlotSnapshot(
            setlist: setlist,
            entry: entry,
            record: record,
            number: 1,
            total: 1,
        )))
        let output = try await Support.make(
            snapshot,
            Support.options(.lyrics) { $0.stageNotes = true },
        )
        let text = Support.allText(output.pdf)
        // The header's "Key Am" names the key, not a chord.
        let tokens = Self.tokens(text.replacingOccurrences(of: "Key Am", with: ""))
        for word in Self.lyricWords(StageWindowSuites.SingerViewSnapshotTests.kitaabon) {
            #expect(tokens.contains(word), "the sheet lacks \(word)")
        }
        let chords = tokens.intersection(Self.chordNames)
        #expect(chords.isEmpty, "the sheet prints chords \(chords)")
        // The sounding key and no capo (R178); Chords only as a first line tagged CHORDS.
        #expect(text.contains("Key Am, 84"))
        #expect(!text.contains("capo"))
        #expect(text.contains("CHORDS"))
        #expect(text.contains("Instrumental"))
        #expect(text.contains("All together"))
        // Cues print with the option; song and slot notes never in a lyric sheet.
        #expect(text.contains("Softly"))
        #expect(!text.contains("Count in four"))
        #expect(!text.contains("Watch Ravi"))
        // The unlabelled lead-in is left out of the sheet and its map line.
        #expect(!text.contains("Lead-in"))
        #expect(text.contains("Intro \u{00B7} V1 \u{00B7} Ch \u{00B7} V2 \u{00B7} Ch 2/3"))
        #expect(output.document.fileName == "Kitaabon Wali Gali (Lyrics).pdf")
        let keywords = output.pdf.documentAttributes?[PDFDocumentAttribute.keywordsAttribute]
        #expect((keywords as? [String])?.contains("lyrics") == true)
        try Support.writePages(output.pdf, name: "lyrics-slot", folder: Self.folder)
    }

    @Test
    func `a lyric songbook shows sounding keys and draws no diagrams or fills`() async throws {
        let capo = Support.record(SingerPreviewTests.song, index: 5)
        var fill = Support.record(StageWindowSuites.StageFillTests.song, index: 6)
        fill.sidecar.displayPrefs.showDiagrams = true
        let setlist = Setlist(id: Support.setlistID(), name: "Friday Set", entries: [
            SetlistEntry(itemId: Support.item(0), songId: capo.id),
            SetlistEntry(itemId: Support.item(1), songId: fill.id),
        ])
        var profile = InstrumentProfile()
        profile.bassNotes = true
        let output = try await Support.make(
            Support.snapshot(.setlist(setlist, [capo.id: capo, fill.id: fill]), profile: profile),
            Support.options(.lyrics) { $0.diagrams = .all },
        )
        let list = Support.text(output.pdf, page: 0)
        // G with capo 2 sounds in A: the set list and the header say "Key A".
        #expect(list.contains("Key A"))
        #expect(!list.contains("capo"))
        let sheet = Support.text(output.pdf, page: 1)
        #expect(sheet.contains("Key A, 96"))
        #expect(sheet.contains("Tujh mein rab dikhta hai"))
        #expect(output.diagrams.isEmpty)
        for song in output.job.songs {
            #expect(song.request.view == .singer)
            #expect(song.request.walkUps == nil)
            #expect(song.request.notes.isEmpty)
            #expect(song.header.scale == nil)
        }
        #expect(output.document.fileName == "Friday Set (Lyrics).pdf")
        // Large by default for lyrics (spec 8.3).
        #expect(output.job.songs[0].request.style.maxLyricSize == PrintTextSize.large.lyricSize)
        try Support.writePages(output.pdf, name: "lyrics-songbook", folder: Self.folder)
    }

    @Test
    func `the lyrics part keeps its own text size, large by default`() throws {
        var options = PrintOptions(part: .chords)
        #expect(options.textSize == .medium)
        options.part = .lyrics
        #expect(options.textSize == .large)
        options.textSize = .small
        #expect(options.lyricsSize == .small)
        #expect(options.size == .medium)
        let data = try JSONEncoder().encode(options.remembered)
        let decoded = try JSONDecoder().decode(RememberedPrintOptions.self, from: data)
        #expect(decoded.lyricsSize == .small)
        let old = try JSONDecoder().decode(
            RememberedPrintOptions.self,
            from: Data(#"{"paper":"letter","size":"small"}"#.utf8),
        )
        #expect(old.lyricsSize == .large)
    }
}
