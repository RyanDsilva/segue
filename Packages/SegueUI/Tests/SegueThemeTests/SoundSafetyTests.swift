import AppKit
import Foundation
import MusicTheory
import Playback
@testable import SegueUI
import Shows
import Synchronization
import Testing

/// No sound in a gig, by construction (P8-6 section 9, R161): the player cannot be made
/// while a gig runs, starting a gig stops and releases it and blocks the engine before the
/// stage is presented, and every entry point stays silent until the gig ends.
extension StageWindowSuites {
    @MainActor
    @Suite(.serialized)
    struct SoundSafetyTests {
        static let songs = ["{title: A}\n{key: G}\n{tempo: 100}\n[G]La [C]la [D]la\n"]

        static func chordPhrase() throws -> Phrase {
            let chord = try #require(ChordSymbol(parsing: "G"))
            return PhraseBuilder.chord(chord, sound: .piano, style: .block, bass: 31)
        }

        @Test(arguments: [ShowKind.gig, .rehearsal])
        func `the player exists exactly outside a gig`(kind: ShowKind) async throws {
            let run = try await MetronomeRun(songs: Self.songs)
            let live = try await run.start(kind)
            let sound = run.app.sound
            // Exhaustive, so a new kind has to decide.
            switch kind {
            case .gig:
                #expect(sound.gate.gigRunning)
                #expect(sound.makePlayer() == nil)
                #expect(SoundPlayer(
                    gate: sound.gate,
                    makeOutput: { RecordingSoundOutput(clock: nil) },
                    clock: run.env.clock,
                    settings: sound.settings,
                ) == nil)
                #expect(run.app.dependencies.audio.isBlocked)
                #expect(!sound.isAvailable)
            case .rehearsal:
                #expect(!sound.gate.gigRunning)
                #expect(sound.makePlayer() != nil)
                #expect(!run.app.dependencies.audio.isBlocked)
                #expect(sound.isAvailable)
            }
            try await run.end(live)
        }

        @Test
        func `in a gig every entry point stays silent, and sound works again after it`(
        ) async throws {
            let run = try await MetronomeRun(songs: Self.songs)
            let live = try await run.start(.gig)
            #expect(try !run.app.sound.play(Self.chordPhrase()))
            try await SoundEntryPoints.driveAll(run.app)
            #expect(run.sounds.made == 0)
            #expect(run.app.dependencies.audio.isBlocked)
            try await run.end(live)
            #expect(!run.app.dependencies.audio.isBlocked)
            #expect(run.app.sound.player == nil) // nothing restarted by itself
            #expect(try run.app.sound.play(Self.chordPhrase()))
            #expect(run.sounds.made == 1)
        }

        @Test
        func `a single-song Live session is a gig too`() async throws {
            let run = try await MetronomeRun(songs: Self.songs)
            let session = try #require(run.app.session)
            let song = try #require(session.library.catalog.first)
            #expect(await run.app.startSongSession(song.id, kind: .gig))
            let live = try #require(run.app.live)
            #expect(run.app.sound.gate.gigRunning)
            try await SoundEntryPoints.driveAll(run.app)
            #expect(run.sounds.made == 0)
            #expect(run.app.dependencies.audio.isBlocked)
            live.dispatch(.endShow)
            live.confirmEnd()
            _ = try await run.env.waitFor { run.app.live == nil ? true : nil }
            #expect(!run.app.sound.gate.gigRunning)
        }

        @Test
        func `starting a gig stops the sound, releases it and blocks the engine first`(
        ) async throws {
            let run = try await MetronomeRun(songs: Self.songs)
            let presentedAtStop = Mutex<[Bool]>([])
            run.sounds.onStop = {
                let presented = MainActor.assumeIsolated {
                    StageWindowController.shared.stageWindow?.isVisible ?? false
                }
                presentedAtStop.withLock { $0.append(presented) }
            }
            var player = run.app.sound.makePlayer()
            #expect(player != nil)
            try player?.loop(Self.chordPhrase())
            #expect(player?.isPlaying == true)
            weak let weakPlayer = player
            player = nil
            let live = try await run.start(.gig)
            #expect(presentedAtStop.withLock { $0 } == [false])
            #expect(run.app.sound.player == nil)
            #expect(run.app.dependencies.audio.isBlocked)
            #expect(weakPlayer == nil)
            #expect(run.sounds.last == nil) // the output went with the player
            try await run.end(live)
        }

        @Test
        func `a rehearsal stops editor sound but keeps sound available`() async throws {
            let run = try await MetronomeRun(songs: Self.songs)
            let player = try #require(run.app.sound.makePlayer())
            try player.play(Self.chordPhrase())
            let live = try await run.start(.rehearsal)
            #expect(!player.isPlaying)
            #expect(run.sounds.last?.stops == 1)
            #expect(!run.app.dependencies.audio.isBlocked)
            try await run.end(live)
        }
    }
}

/// Drives every sound entry point outside the stage, as a user would (P8-6 section 9).
@MainActor
enum SoundEntryPoints {
    static func driveAll(_ app: AppModel) async throws {
        // Settings > Audio "Test".
        app.sound.testSound()
        // A library preview chord, a diagram cell's chord and a bass cell's note.
        let library = try #require(app.session?.library)
        let record = try #require(library.catalog.first)
        let render = SongSummary.renderModel(record)
        let hearing = try #require(library.chordHearing(render))
        #expect(!hearing.isEnabled)
        let chord = try #require(HearChordTests.chords(render).first)
        hearing.play(chord)
        hearing.playConcert("G")
        hearing.playBass(31)
        // The walk-up picker's and the Walk-ups list's play buttons.
        for audition in [
            library.walkUpAudition(render),
            library.walkUpAudition(songID: record.id),
        ] {
            let audition = try #require(audition)
            #expect(!audition.isEnabled)
            #expect(audition.player() == nil)
        }
    }
}
