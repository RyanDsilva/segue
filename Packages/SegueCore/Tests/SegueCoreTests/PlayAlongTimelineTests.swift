import ChordPro
import Editing
import Foundation
import Library
import MusicTheory
@testable import Playback
import Shows
import Testing

/// Play-along as a slice of the one `SongTimeline` plus voices (P8-6 sections 7.5, 15.1 as
/// amended by P8-7): ranges, walk-ups from `ChordChange.shown`, strong beats, count-in,
/// tempo map, pushes, fills, through real render models and bass lines.
struct PlayAlongTimelineTests {
    static let placement = BassPlacement(tuning: .bassStandard4, home: 3)
    static let all: Set<VoiceToggle> = [.bass, .chords, .click, .walkUps]

    struct Song {
        var document: SongDocument
        var model: RenderModel
        var units: [SongSectionUnit]
        var prefs: BassPrefs

        init(_ source: String, prefs: BassPrefs = BassPrefs()) {
            (document, _) = ChordProParser.parse(source)
            let options = DisplayOptions()
                .withBass(InstrumentProfile(bassNotes: true, walkUps: .everyChange))
            model = RenderModel(document: document, options: options)
            units = SongSections.units(of: document)
            self.prefs = prefs
        }

        func timeline(order: [PlayedPass]? = nil) -> SongTimeline {
            SongTimeline.build(
                document: document,
                sections: model.sections,
                units: units,
                timing: prefs.timing,
                order: order,
            )
        }

        func playAlong(
            _ range: PlayAlongRange = .whole,
            walkUps: Bool = true,
            fills: [PlayAlongFill] = [],
        ) -> PlayAlongTimeline {
            PlayAlongTimeline.make(
                timeline: timeline(),
                range: range,
                changes: walkUps
                    ? BassLine.changes(model, document: document, prefs: prefs) : [],
                fills: fills,
                transform: model.transform,
                placement: PlayAlongTimelineTests.placement,
            )
        }

        func override(_ position: ChordPosition, beats: Int, push: Push? = nil) throws
            -> ChordBeatsOverride
        {
            let anchor = try #require(ChordAnchors.anchor(
                at: position,
                units: units,
                sections: model.sections,
            ))
            return ChordBeatsOverride(anchor: anchor, beats: beats, push: push)
        }
    }

    static func phrase(
        _ timeline: PlayAlongTimeline,
        voices: Set<VoiceToggle> = all,
        factor: Double = 1,
        countIn: Bool = false,
    ) -> Phrase {
        PhraseBuilder.playAlong(
            timeline,
            voices: voices,
            sound: .piano,
            style: .block,
            factor: factor,
            countIn: countIn,
        )
    }

    /// "31@0.000" per bass event.
    static func bass(_ phrase: Phrase) -> [String] {
        phrase.events.filter { $0.voice == .bass }.map { event in
            "\(event.note)@\(String(format: "%.3f", event.onset))"
        }
    }

    static func onsets(_ phrase: Phrase, _ voice: (Voice) -> Bool) -> [Double] {
        phrase.events.filter { voice($0.voice) }.map { ($0.onset * 1000).rounded() / 1000 }
    }

    static func isClick(_ voice: Voice) -> Bool {
        if case .click = voice {
            return true
        }
        return false
    }

    static let song = """
    {key: G}
    {start_of_verse: Verse}
    [G]Hello [C]there
    {end_of_verse}
    {start_of_chorus}
    [D]Sing [G]it
    {end_of_chorus}
    {chorus}

    """

    // MARK: Ranges

    @Test
    func `a section plays alone from tick 0 and a range runs to the end`() {
        let song = Song(Self.song)
        let chorus = song.playAlong(.section(1))
        #expect(chorus.timeline.chords.map(\.token) == ["D", "G"])
        #expect(chorus.timeline.chords.first?.onset == 0)
        #expect(chorus.passes == 1 ..< 2)
        let rest = song.playAlong(.from(1))
        #expect(rest.timeline.chords.map(\.token) == ["D", "G", "D", "G"])
        #expect(song.playAlong(.section(9)).chords.isEmpty)
    }

    @Test
    func `the range rounds up to whole bars by lengthening its last chord`() {
        var prefs = BassPrefs()
        prefs.timing.rule = .beats(3)
        let song = Song("[G]a [C]b\n", prefs: prefs)
        let timeline = song.playAlong()
        #expect(timeline.timeline.chords.map(\.length) == [1440, 480 * 5])
        #expect(timeline.timeline.totalTicks == 8 * 480)
        // At 90 BPM, two bars of 4/4.
        #expect(abs(timeline.duration() - 8 * 60 / 90) < 1e-9)
    }

    // MARK: Bass

    @Test
    func `roots sit on beats 1 and 3 in 4/4 and on beat 1 in 3/4`() {
        let common = Song("[G]a [C]b\n").playAlong(walkUps: false)
        #expect(Self.bass(Self.phrase(common)) == ["31@0.000", "31@1.333", "36@2.667", "36@4.000"])
        let waltz = Song("{time: 3/4}\n[G]a [C]b\n").playAlong(walkUps: false)
        #expect(Self.bass(Self.phrase(waltz)) == ["31@0.000", "36@2.000"])
    }

    @Test
    func `a compound meter plays a root on every dotted-quarter pulse`() {
        let song = Song("{time: 6/8}\n{tempo: 60}\n[G]a [C]b\n").playAlong(walkUps: false)
        #expect(Self.bass(Self.phrase(song)) == ["31@0.000", "31@1.000", "36@2.000", "36@3.000"])
    }

    @Test
    func `the shown walk-up plays on the last beats and the next root lands a step away`() throws {
        let song = Song("{key: G}\n[G]Hello [C]there\n")
        let change = try #require(BassLine.changes(
            song.model,
            document: song.document,
            prefs: song.prefs,
        ).first)
        let shown = try #require(change.shown)
        let timeline = song.playAlong()
        #expect(timeline.chords[0].walk == shown.offsets)
        let bass = Self.phrase(timeline).events.filter { $0.voice == .bass }
        let interval = 60.0 / 90
        // The walk takes the last beats of bar 1; the beat-3 root goes when a note takes it.
        let walkStart = Double(4 - shown.offsets.count) * interval
        let walk = bass.filter { $0.onset > walkStart - 0.001 && $0.onset < 4 * interval - 0.001 }
        #expect(walk.count == shown.offsets.count)
        #expect(abs((walk.first?.onset ?? 0) - walkStart) < 1e-6)
        // Stepwise into C: the landing is the last walk note minus its offset.
        let last = try #require(walk.last)
        let landing = try #require(bass.first { abs($0.onset - 4 * interval) < 1e-6 })
        #expect(Int(landing.note) == Int(last.note) - (shown.offsets.last ?? 0))
        // With Walk-ups off, roots only.
        let roots = Self.phrase(timeline, voices: [.bass])
        #expect(Self.bass(roots) == ["31@0.000", "31@1.333", "36@2.667", "36@4.000"])
    }

    @Test
    func `a chorus stub borrows the chorus's walk-ups in written order`() {
        let song = Song(Self.song)
        let timeline = song.playAlong()
        // Passes: Verse, Chorus, the stub (Chorus again). D -> G inside each chorus.
        let chorus = timeline.chords.filter { $0.timed.token == "D" }
        #expect(chorus.count == 2)
        #expect(chorus[0].walk == chorus[1].walk)
    }

    @Test
    func `played passes share one correction and walk per pass`() throws {
        let song = try Song(Self.song, prefs: BassPrefs(timing: ChordTiming(chords: [
            Song(Self.song).override(ChordPosition(section: 1, chord: 0), beats: 2),
        ])))
        let order = [PlayedPass(index: 1), PlayedPass(index: 0), PlayedPass(index: 1)]
        let arranged = ArrangedSections.build(song.model.sections, order: order)
        let context = try #require(BassLine.context(
            for: song.model,
            document: song.document,
            prefs: song.prefs,
        ))
        let changes = BassLine.changes(
            arranged.map(\.section),
            origins: arranged.map(\.source),
            context: context,
        )
        let timeline = PlayAlongTimeline.make(
            timeline: song.timeline(order: order),
            range: .from(1),
            changes: changes,
            transform: song.model.transform,
            placement: Self.placement,
        )
        #expect(timeline.timeline.chords.map(\.token) == ["G", "C", "D", "G"])
        #expect(timeline.timeline.chords.map(\.length) == [1920, 1920, 960, 1920 + 960])
        #expect(timeline.passes == 1 ..< 3)
    }

    // MARK: Chords and click

    @Test
    func `voice toggles filter events and N.C. is silent while the click goes on`() {
        let song = Song("[G]a [N.C.]b [C]c\n").playAlong(walkUps: false)
        let chordsOnly = Self.phrase(song, voices: [.chords])
        #expect(chordsOnly.events.allSatisfy { $0.voice == .chord })
        #expect(Self.onsets(chordsOnly) { $0 == .chord }.uniqued() == [0, 5.333])
        let clickOnly = Self.phrase(song, voices: [.click])
        #expect(clickOnly.events.count == 12)
        #expect(clickOnly.events.first?.voice == .click(.downbeat))
        #expect(clickOnly.events[1].voice == .click(.plain))
        #expect(clickOnly.events[4].voice == .click(.downbeat))
        #expect(Self.phrase(song, voices: [.bass]).events.allSatisfy {
            $0.onset < 2.667 - 0.001 || $0.onset > 5.333 - 0.001
        })
    }

    @Test
    func `a chord longer than a bar is struck again on each downbeat`() {
        var prefs = BassPrefs()
        prefs.timing.rule = .each(.twoBars)
        let song = Song("[G]a\n", prefs: prefs).playAlong(walkUps: false)
        let phrase = Self.phrase(song, voices: [.chords])
        #expect(Self.onsets(phrase) { $0 == .chord }.uniqued() == [0, 2.667])
    }

    @Test
    func `the count-in is one bar of click before the first chord`() {
        let song = Song("{time: 3/4}\n{tempo: 120}\n[G]a\n").playAlong()
        let phrase = Self.phrase(song, voices: [.bass], countIn: true)
        #expect(Self.onsets(phrase, Self.isClick) == [0, 0.5, 1.0])
        #expect(phrase.events.first?.voice == .click(.downbeat))
        #expect(Self.onsets(phrase) { $0 == .bass }.first == 1.5)
        #expect(abs(phrase.length - 3.0) < 1e-9)
    }

    // MARK: Tempo map, factor and pushes

    @Test
    func `a mid-song tempo changes onsets from where it is written`() {
        let song = Song("{tempo: 120}\n[G]a\n\n{tempo: 60}\n[C]b [D]c\n").playAlong(walkUps: false)
        let roots = Self.onsets(Self.phrase(song, voices: [.bass])) { $0 == .bass }
        // G: 4 beats at 120 (2 s), then C and D at 60 (4 s each).
        #expect(roots == [0, 1, 2, 4, 6, 8])
    }

    @Test
    func `the session factor scales every onset`() {
        let song = Song("{tempo: 120}\n[G]a [C]b\n").playAlong(walkUps: false)
        let full = Self.onsets(Self.phrase(song, voices: [.bass])) { $0 == .bass }
        let half = Self.onsets(Self.phrase(song, voices: [.bass], factor: 0.5)) { $0 == .bass }
        #expect(half == full.map { $0 * 2 })
    }

    @Test
    func `a pushed chord strikes early and the click stays on the grid`() throws {
        let plain = Song("{tempo: 60}\n[G]a [C]b\n")
        let song = try Song("{tempo: 60}\n[G]a [C]b\n", prefs: BassPrefs(timing: ChordTiming(
            chords: [plain.override(ChordPosition(section: 0, chord: 1), beats: 4, push: .eighth)],
        ))).playAlong(walkUps: false)
        let phrase = Self.phrase(song, voices: [.chords, .bass, .click])
        #expect(Self.onsets(phrase) { $0 == .chord }.uniqued() == [0, 3.5])
        #expect(Self.onsets(phrase) { $0 == .bass }.contains(3.5))
        #expect(Self.onsets(phrase, Self.isClick) == [0, 1, 2, 3, 4, 5, 6, 7])
    }

    // MARK: Fills (P8-7 section 13)

    @Test
    func `a fill replaces the roots and the walk-up over its region`() {
        let fill = PlayAlongFill(region: 960 ..< 1920, notes: [
            PlayAlongFill.Note(tick: 960, length: 480, midi: 33),
            PlayAlongFill.Note(tick: 1440, length: 480, midi: 35, velocity: 70),
        ])
        let song = Song("{key: G}\n{tempo: 60}\n[G]Hello [C]there\n").playAlong(fills: [fill])
        let bass = Self.phrase(song, voices: [.bass, .walkUps]).events.filter { $0.voice == .bass }
        #expect(bass.map(\.note) == [31, 33, 35, 36, 36])
        #expect(bass.map(\.onset) == [0, 2, 3, 4, 6])
        // The root ringing into the region is cut at its start.
        #expect(bass[0].duration == 2)
        #expect(bass[2].velocity == 70)
    }

    // MARK: Time

    @Test
    func `the tick clock turns seconds back into ticks`() {
        let song = Song("{tempo: 120}\n[G]a\n\n{tempo: 60}\n[C]b\n").playAlong()
        let clock = song.clock()
        #expect(clock.seconds(1920) == 2)
        #expect(clock.tick(atSeconds: 2) == 1920)
        #expect(clock.tick(atSeconds: 3) == 1920 + 480)
        #expect(clock.tick(atSeconds: -1) == 0)
        #expect(clock.tick(atSeconds: 99) == song.timeline.totalTicks)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
