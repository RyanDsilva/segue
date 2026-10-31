import AppKit
import ChordPro
import Diagrams
import Editing
import LiveLayout
import MusicTheory
@testable import SegueUI
import SwiftUI
import Testing

/// The stage mini neck (P8-4 7.3, 11.3): what it shows for a chord, its accessibility value,
/// and its drawing in the stage's dark theme.
@MainActor
struct StageBassNeckTests {
    static func transform(key: String?, capo: Int?) -> DisplayTransform {
        DisplayTransform(
            options: DisplayOptions(),
            key: KeyContext(declared: key.flatMap(SongKey.init(parsing:)), detection: nil),
            capo: capo,
        )
    }

    @Test
    func `the neck shows the sounding bass note in the box around the key`() throws {
        // Key G with capo 2 sounds in A: home is A on the E string, fret 5.
        let transform = Self.transform(key: "G", capo: 2)
        let home = StageBassNeckState.home(
            transform: transform,
            firstChord: nil,
            tuning: .bassStandard4,
        )
        #expect(home == 5)
        let state = try #require(StageBassNeckState.make(
            chord: "G/B",
            transform: transform,
            home: home,
            tuning: .bassStandard4,
        ))
        #expect(state.note == "C#")
        #expect(state.suggested == FretPosition(string: 1, fret: 4))
        #expect(state.positionText == "A4")
        #expect(state.accessibilityValue == "C#, A string fret 4; tones R, 3, 5")
        #expect(state.window == 4 ... 8)
        // R166: every tone of A/C# in the window, the note to play (C#) strongest.
        #expect(Set(state.tones.map { "\($0.position) \($0.degree) \($0.role)" }) == [
            "0:5 R root", "1:4 3 bass", "1:7 5 tone", "2:7 R root", "3:6 3 bass",
        ])
    }

    @Test
    func `the walk-up out of the chord is numbered on the neck`() throws {
        let transform = Self.transform(key: "G", capo: nil)
        let state = try #require(StageBassNeckState.make(
            chord: "G",
            transform: transform,
            home: 3,
            tuning: .bassStandard4,
        ))
        let run = ApproachRun(
            change: ChangeID(from: ChordPosition(section: 0, chord: 0), toBass: PitchClass(0)),
            notes: ["A", "B"],
            chromatic: [false, false],
            isPick: false,
            accessibility: "walk up A, B into C",
            pitches: [PitchClass(9), PitchClass(11)],
            ascending: true,
        )
        let walked = state.with(walkUp: run)
        #expect(walked.walkUp == [
            .init(number: 1, position: FretPosition(string: 0, fret: 5)),
            .init(number: 2, position: FretPosition(string: 1, fret: 2)),
        ])
        #expect(walked.accessibilityValue == "G, E string fret 3; tones R, 3, 5; walk-up 2 notes")
        #expect(state.with(walkUp: nil) == state)
        var dimmed = state
        dimmed.dimmed = true
        #expect(dimmed.with(walkUp: run).walkUp.isEmpty)
    }

    @Test
    func `a fill's notes are numbered across the whole fill, a pin at its string`() throws {
        let transform = Self.transform(key: "G", capo: nil)
        let state = try #require(StageBassNeckState.make(
            chord: "C",
            transform: transform,
            home: 3,
            tuning: .bassStandard4,
        ))
        // The second chord of a fill: its notes D and E are the fill's 3rd and 4th of 5; E is
        // pinned to the D string (fret 2), D is walked from C on the A string.
        let run = FillRun(
            part: "fill",
            notes: ["D", "E"],
            chromatic: [false, false],
            isLast: true,
            accessibility: "fill: D, E into G",
            pitches: [PitchClass(2), PitchClass(4)],
            pins: [nil, FretPosition(string: 2, fret: 2)],
            firstNumber: 3,
            total: 5,
        )
        let filled = state.with(fill: run)
        #expect(filled.walkUp == [
            .init(number: 3, position: FretPosition(string: 1, fret: 5)),
            .init(number: 4, position: FretPosition(string: 2, fret: 2)),
        ])
        #expect(filled.accessibilityValue.hasSuffix("; fill: 5 notes"))
        #expect(!filled.accessibilityValue.contains("walk-up"))
        // A pin outside the window is left out, its number kept on the others.
        var far = run
        far.pins = [nil, FretPosition(string: 2, fret: 14)]
        #expect(state.with(fill: far).walkUp.map(\.number) == [3])
        var dimmed = state
        dimmed.dimmed = true
        #expect(dimmed.with(fill: run).walkUp.isEmpty)
    }

    @Test
    func `the Settings strings and tuning with or without the profile`() throws {
        let transform = Self.transform(key: "D", capo: nil)
        // R163: the neck uses the Settings tuning for anyone, not only for "I play bass".
        let standard = InstrumentProfile(bassNotes: true)
        let anyone = InstrumentProfile(strings: 5, tuning: .bassStandard5, bassNotes: true)
        let bassist = InstrumentProfile(
            playsBass: true,
            strings: 5,
            tuning: .bassStandard5,
            bassNotes: true,
        )
        for (profile, expected) in [
            (standard, FretPosition(string: 1, fret: 5)),
            (anyone, FretPosition(string: 0, fret: 3)),
            (bassist, FretPosition(string: 0, fret: 3)),
        ] {
            let tuning = try #require(profile.bassView?.tuning)
            let home = StageBassNeckState.home(
                transform: transform,
                firstChord: nil,
                tuning: tuning,
            )
            let state = try #require(StageBassNeckState.make(
                chord: "D",
                transform: transform,
                home: home,
                tuning: tuning,
            ))
            #expect(state.suggested == expected)
        }
    }

    @Test
    func `no key homes on the first bass note and N.C. has no neck`() {
        let transform = Self.transform(key: nil, capo: nil)
        #expect(StageBassNeckState.home(
            transform: transform,
            firstChord: "C/E",
            tuning: .bassStandard4,
        ) == 0)
        #expect(StageBassNeckState.make(
            chord: "N.C.",
            transform: transform,
            home: 0,
            tuning: .bassStandard4,
        ) == nil)
        let open = StageBassNeckState.make(
            chord: "Em",
            transform: transform,
            home: 3,
            tuning: .bassStandard4,
        )
        #expect(open?.accessibilityValue == "E, E string open; tones R, b3, 5")
        #expect(open?.window == 0 ... 4)
    }

    /// A walk up from the root by two whole steps (G: A B; Am7: B C#).
    static func walkUpTwoSteps(_ chord: String) throws -> ApproachRun {
        let root = try #require(ChordSymbol(parsing: chord)).root.pitchClass
        return ApproachRun(
            change: ChangeID(from: ChordPosition(section: 0, chord: 0), toBass: root),
            notes: [],
            chromatic: [],
            isPick: false,
            accessibility: "",
            pitches: [root.transposed(by: 2), root.transposed(by: 4)],
            ascending: true,
        )
    }

    @Test
    func `the neck draws in light and dark`() throws {
        let transform = Self.transform(key: "G", capo: nil)
        struct Case {
            var name: String
            var chord: String
            var tuning: Tuning
        }
        let cases = [
            Case(name: "b-eadg", chord: "G/B", tuning: .bassStandard4),
            Case(name: "em-open", chord: "Em", tuning: .bassStandard4),
            Case(name: "d-beadg", chord: "D", tuning: .bassStandard5),
            Case(name: "g7-walk", chord: "G7", tuning: .bassStandard4),
            Case(name: "am7-beadg-walk", chord: "Am7", tuning: .bassStandard5),
        ]
        for item in cases {
            var state = try #require(StageBassNeckState.make(
                chord: item.chord,
                transform: transform,
                home: 3,
                tuning: item.tuning,
            ))
            if item.name.hasSuffix("-walk") {
                state = try state.with(walkUp: Self.walkUpTwoSteps(item.chord))
            }
            for dimmed in [false, true] {
                state.dimmed = dimmed
                for dark in [false, true] {
                    let renderer = ImageRenderer(content: StageBassNeck(state: state)
                        .padding(12)
                        .frame(width: StageBassNeck.width + 24, height: StageBassNeck.height + 24)
                        .background(Theme.color.ground)
                        .environment(\.colorScheme, dark ? .dark : .light))
                    // The stage's Retina scale, so the labels are judged as drawn.
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    let suffix = (dimmed ? "-dimmed" : "") + (dark ? "-dark" : "-light")
                    try DiagramSnapshotTests.writePNG(
                        image,
                        to: DiagramSnapshotTests
                            .screenshotDirectory.deletingLastPathComponent()
                            .appending(path: "bass-neck/\(item.name)\(suffix).png"),
                    )
                }
            }
        }
    }
}

/// A song whose parts each sit on one chord, long enough to scroll in one column: verse on G,
/// chorus on C, verse 2 on D, bridge on E, key G with capo 2 (so it sounds in A).
enum BassStageSong {
    static func source() -> String {
        func block(_ open: String, _ close: String, _ chord: String) -> String {
            let lines = (1 ... 6).map { "[\(chord)]Line \($0) of the song here" }
            return "{\(open)}\n" + lines.joined(separator: "\n") + "\n{\(close)}\n"
        }
        return "{title: Harbour}\n{key: G}\n{capo: 2}\n\n"
            + block("start_of_verse: Verse 1", "end_of_verse", "G") + "\n"
            + block("start_of_chorus", "end_of_chorus", "C") + "\n"
            + block("start_of_verse: Verse 2", "end_of_verse", "D") + "\n"
            + block("start_of_bridge", "end_of_bridge", "Em")
    }

    static func chords(_ plan: LayoutPlan?) -> [String] {
        guard let plan else { return [] }
        return Array(Set(StagePasses.placedChords(in: plan).map(\.text))).sorted()
    }
}

/// `B` on a real stage and the mini neck in the status band (P8-4 6.5, 7.3, 11.3).
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct StageBassTests {
        @Test
        func `the b key flips the store, relayouts and flashes, with or without the profile`(
        ) async throws {
            let run = try await MetronomeRun(songs: [
                BassStageSong.source(),
                "{title: Two}\n[G]La\n",
            ])
            let live = try await run.start(.gig)
            live.setViewport(MapSong.viewport)
            let store = run.app.instrumentProfile
            #expect(BassStageSong.chords(live.plan) == ["C", "D", "Em", "G"])
            #expect(live.currentModel?.header.scale == nil)

            live.dispatch(.toggleBassNotes)
            #expect(store.profile.bassNotes)
            #expect(!store.profile.playsBass)
            #expect(live.indicator == "Bass notes")
            // Sounding pitch: capo 2 puts G C D Em at A D E F#.
            #expect(BassStageSong.chords(live.plan) == ["A", "D", "E", "F#"])
            #expect(live.currentModel?.header.scale == "A major: A B C# D E F# G#")
            #expect(StageScaleLine.spoken("A major: A B C# D E F# G#")
                == "Sounding key A major, scale A, B, C sharp, D, E, F sharp, G sharp")
            #expect(StageScaleLine.spoken("Bbm: Bb C Db Eb F Gb Ab").hasPrefix(
                "Sounding key B flat minor, scale B flat, C, D flat",
            ))

            live.dispatch(.toggleBassNotes)
            #expect(!store.profile.bassNotes)
            #expect(live.indicator == "Chords")
            #expect(BassStageSong.chords(live.plan) == ["C", "D", "Em", "G"])

            // With the profile the same key does the same.
            store.update { $0.setPlaysBass(true) }
            live.relayout()
            #expect(BassStageSong.chords(live.plan) == ["A", "D", "E", "F#"])
            live.dispatch(.toggleBassNotes)
            #expect(BassStageSong.chords(live.plan) == ["C", "D", "Em", "G"])
            try await run.end(live)
        }

        @Test
        func `the neck shows only with the bass view and its neck on and follows the scroll`(
        ) async throws {
            let run = try await MetronomeRun(songs: [
                BassStageSong.source(),
                "{title: Two}\n[G]La\n",
            ])
            let live = try await run.start(.rehearsal)
            live.setViewport(MapSong.viewport)
            let store = run.app.instrumentProfile
            #expect(!live.showsBassNeck)
            store.update { $0.bassNotes = true }
            live.relayout()
            #expect(live.showsBassNeck)
            let plan = try #require(live.plan)
            #expect(plan.needsScroll)
            let now = run.env.clock.now()
            // Verse 1 on G sounds A; EADG home is A on the E string, fret 5.
            let first = try #require(live.bassNeck(at: now))
            #expect(first.note == "A")
            #expect(first.accessibilityValue == "A, E string fret 5; tones R, 3, 5")
            #expect(first.tuning == .bassStandard4)

            // Page down chord by chord: the neck follows the reading line.
            var notes = [first.note]
            for _ in 0 ..< 12 {
                live.dispatch(.scrollPageDown)
                if let note = live.bassNeck(at: run.env.clock.now())?.note, note != notes.last {
                    notes.append(note)
                }
            }
            #expect(notes == ["A", "D", "E", "F#"])

            // The bassist's five strings.
            store.update {
                $0.setPlaysBass(true)
                $0.setStrings(5)
            }
            live.relayout()
            #expect(live.bassNeck(at: run.env.clock.now())?.tuning == .bassStandard5)

            store.update { $0.stageNeck = false }
            live.relayout()
            #expect(!live.showsBassNeck)
            #expect(live.bassNeck(at: run.env.clock.now()) == nil)
            try await run.end(live)
        }

        @Test
        func `the stage and the preview draw bass notes with the chord beside`() async throws {
            let run = try await MetronomeRun(songs: [
                BassStageSong.source(),
                "{title: Two}\n[G]La\n",
            ])
            run.app.instrumentProfile.update {
                $0.bassNotes = true
                $0.chordBeside = true
            }
            let live = try await run.start(.rehearsal)
            let directory = DiagramSnapshotTests.screenshotDirectory.deletingLastPathComponent()
                .appending(path: "bass", directoryHint: .isDirectory)
            let screen = CGSize(width: 1470, height: 956)
            live.setViewport(LiveView.viewport(for: screen, topInset: 0))
            #expect(live.showsBassNeck)
            let stage = ImageRenderer(content: LiveView(session: live)
                .frame(width: screen.width, height: screen.height)
                .environment(\.colorScheme, .dark))
            stage.scale = 2
            try DiagramSnapshotTests.writePNG(
                #require(stage.cgImage),
                to: directory.appending(path: "stage.png"),
            )
            let model = try #require(live.currentModel)
            for dark in [false, true] {
                let page = ImageRenderer(content: SongPageView(model: model, selectable: false)
                    .padding(24)
                    .frame(width: 720, alignment: .topLeading)
                    .background(Theme.color.ground)
                    .environment(\.colorScheme, dark ? .dark : .light))
                page.scale = 2
                try DiagramSnapshotTests.writePNG(
                    #require(page.cgImage),
                    to: directory.appending(path: "preview-\(dark ? "dark" : "light").png"),
                )
            }
            try await run.end(live)
        }

        @Test
        func `the neck hides in a break`() async throws {
            let run = try await MetronomeRun(
                songs: [BassStageSong.source(), "{title: Two}\n[G]La\n"],
                breakBefore: 1,
            )
            run.app.instrumentProfile.update { $0.bassNotes = true }
            let live = try await run.start(.gig)
            #expect(live.showsBassNeck)
            live.dispatch(.next)
            _ = try await run.env.waitFor { live.state.record.currentBreak != nil ? true : nil }
            #expect(!live.showsBassNeck)
            try await run.end(live)
        }
    }
}
