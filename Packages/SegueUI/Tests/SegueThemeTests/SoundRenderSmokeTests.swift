import Foundation
import MusicTheory
import Playback
@testable import SegueUI
import Synchronization
import Testing

/// The one test that touches real audio (P8-6 section 15.3): the real engine host in
/// offline manual rendering with the bundled bank. It renders, never plays.
struct SoundRenderSmokeTests {
    @Test
    func `bass, chord and click land on time from the bundled bank, unclipped`() throws {
        let host = AudioEngineHost(offlineBank: SoundBank.bundledURL)
        let fallbacks = Atomic(0)
        host.onBankFallback = { fallbacks.add(1, ordering: .relaxed) }
        let output = AudioEngineSoundOutput(host: host)
        output.prepare(chord: .piano, bass: .finger)
        let chord = try Voicing.chord(#require(ChordSymbol(parsing: "C")), sound: .piano)
        var events = [NoteEvent(voice: .bass, note: 31, velocity: 96, onset: 0.10, duration: 0.3)]
        for note in chord {
            events.append(NoteEvent(
                voice: .chord,
                note: note,
                velocity: 80,
                onset: 0.5,
                duration: 0.3,
            ))
        }
        events.append(NoteEvent(
            voice: .click(.downbeat),
            note: 0,
            velocity: 100,
            onset: 0.9,
            duration: 0,
        ))
        output.schedule(events, in: 0)
        let samples = host.renderOffline(seconds: 1.2)
        let rate = AudioEngineHost.offlineRate
        #expect(fallbacks.load(ordering: .relaxed) == 0)
        #expect(samples.count == Int(1.2 * rate))

        func peak(_ from: Double, _ to: Double) -> Float {
            samples[Int(from * rate) ..< Int(to * rate)].reduce(0) { max($0, abs($1)) }
        }
        func onset(after start: Double) -> Double? {
            let first = Int(start * rate)
            return samples[first...].firstIndex { abs($0) > 0.001 }.map { Double($0) / rate }
        }
        // Silence before the first note (-60 dBFS), sound in each onset's window.
        #expect(peak(0, 0.10) < 0.001)
        for time in [0.10, 0.50, 0.90] {
            #expect(peak(time, time + 0.15) > 0.001, "nothing sounds at \(time)")
        }
        // The first onset lands within one 512-frame buffer of its time.
        let first = try #require(onset(after: 0))
        #expect(abs(first - 0.10) <= 512 / rate)
        #expect(samples.allSatisfy { abs($0) < 1.0 })
        try Self.checkVoicesAndStop()
    }

    /// Each voice alone, `stopAll` with notes pending: per-voice onsets and the cancel.
    static func checkVoicesAndStop() throws {
        let rate = AudioEngineHost.offlineRate
        for event in [
            NoteEvent(voice: .chord, note: 60, velocity: 80, onset: 0.25, duration: 0.2),
            NoteEvent(voice: .click(.plain), note: 0, velocity: 100, onset: 0.25, duration: 0),
        ] {
            let host = AudioEngineHost(offlineBank: SoundBank.bundledURL)
            AudioEngineSoundOutput(host: host).schedule([event], in: 0)
            let samples = host.renderOffline(seconds: 0.5)
            let first = try #require(samples.firstIndex { abs($0) > 0.001 })
            #expect(abs(Double(first) / rate - 0.25) <= 512 / rate, "\(event.voice) late")
        }
        let host = AudioEngineHost(offlineBank: SoundBank.bundledURL)
        let output = AudioEngineSoundOutput(host: host)
        output.schedule(
            [NoteEvent(voice: .bass, note: 40, velocity: 96, onset: 0.30, duration: 0.3)],
            in: 0,
        )
        _ = host.renderOffline(seconds: 0.1)
        output.stopAll()
        #expect(host.renderOffline(seconds: 0.6).allSatisfy { abs($0) < 0.001 })
    }
}

/// The bundled bank itself (P8-6 section 12.7): small, SF2, and holding every program the
/// app loads. Reads the file, renders nothing.
struct SoundBankBundleTests {
    @Test
    func `the bank is at most 12 MB of SF2 with every program the app loads`() throws {
        let url = try #require(SoundBank.bundledURL)
        let data = try Data(contentsOf: url)
        #expect(data.count <= 12 * 1024 * 1024)
        #expect(data.prefix(4) == Data("RIFF".utf8))
        #expect(data[8 ..< 12] == Data("sfbk".utf8))
        let ifil = try #require(data.range(of: Data("ifil".utf8)))
        let major = UInt16(data[ifil.upperBound + 4]) | UInt16(data[ifil.upperBound + 5]) << 8
        #expect(major == 2) // SF2, never SF3
        let presets = try Self.presets(data)
        let wanted = ChordSound.allCases.map(SoundBank.program)
            + BassSound.allCases.map(SoundBank.program)
        for program in wanted {
            #expect(presets.contains(program), "program \(program) missing")
        }
    }

    /// The bank-0 programs in the `phdr` chunk (38-byte records, the last is EOP).
    static func presets(_ data: Data) throws -> Set<UInt8> {
        let phdr = try #require(data.range(of: Data("phdr".utf8)))
        let size = Int(data[phdr.upperBound]) | Int(data[phdr.upperBound + 1]) << 8
            | Int(data[phdr.upperBound + 2]) << 16 | Int(data[phdr.upperBound + 3]) << 24
        let start = phdr.upperBound + 4
        var programs = Set<UInt8>()
        for record in stride(from: start, to: start + size - 38, by: 38) {
            let program = Int(data[record + 20]) | Int(data[record + 21]) << 8
            let bank = Int(data[record + 22]) | Int(data[record + 23]) << 8
            if bank == 0, program < 128 {
                programs.insert(UInt8(program))
            }
        }
        return programs
    }
}
