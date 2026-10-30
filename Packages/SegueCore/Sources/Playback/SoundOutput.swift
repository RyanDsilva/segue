// P8-6 (docs/phases/8-workstreams/P8-6-audio.md section 6.1, R161): what the app plays, as
// pure note events, and the port they go out through. Pure.

import Foundation
import Shows

/// The chord voice's instrument (Settings > Audio, R161).
public enum ChordSound: String, Sendable, Hashable, Codable, CaseIterable {
    case piano
    case cleanGuitar
}

/// The bass voice's instrument (Settings > Audio; finger by default).
public enum BassSound: String, Sendable, Hashable, Codable, CaseIterable {
    case finger
    case pick
}

/// How a chord is struck: low to high a few milliseconds apart, or all at once.
public enum ChordStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case strum
    case block
}

/// Which instrument an event plays on.
public enum Voice: Sendable, Hashable {
    case bass
    case chord
    case click(MetronomeAccent)
}

/// One note at sounding pitch, timed in seconds from its phrase's start.
public struct NoteEvent: Sendable, Hashable {
    public var voice: Voice
    /// MIDI note at sounding pitch (ignored for `.click`).
    public var note: UInt8
    /// 1 ... 127.
    public var velocity: UInt8
    /// Seconds from the phrase start.
    public var onset: TimeInterval
    public var duration: TimeInterval

    public init(
        voice: Voice,
        note: UInt8,
        velocity: UInt8,
        onset: TimeInterval,
        duration: TimeInterval,
    ) {
        self.voice = voice
        self.note = note
        self.velocity = min(max(velocity, 1), 127)
        self.onset = max(0, onset)
        self.duration = max(0, duration)
    }
}

/// A note placed on a beat grid rather than in seconds: what a generated part (a walk-up, a
/// fill, a pattern) is written as before it meets a tempo. `Phrase(beats:tempo:meter:)`
/// turns it into `NoteEvent`s, so any timed part plays through the same port.
public struct BeatNote: Sendable, Hashable {
    public var voice: Voice
    public var note: UInt8
    public var velocity: UInt8
    /// Pulses from the phrase start (a compound meter's pulse is the dotted quarter, R118).
    public var startBeat: Double
    /// Length in pulses.
    public var beats: Double

    public init(voice: Voice, note: UInt8, velocity: UInt8, startBeat: Double, beats: Double) {
        self.voice = voice
        self.note = note
        self.velocity = velocity
        self.startBeat = startBeat
        self.beats = beats
    }
}

/// Note events and where a loop of them wraps.
public struct Phrase: Sendable, Hashable {
    /// Sorted by onset.
    public var events: [NoteEvent]
    /// Seconds; where a loop wraps.
    public var length: TimeInterval

    public init(events: [NoteEvent], length: TimeInterval) {
        self.events = events.sorted { $0.onset < $1.onset }
        self.length = max(0, length)
    }

    /// `notes` at `tempo` pulses per minute; the length is `lengthBeats` pulses, else up to
    /// the end of the last note.
    public init(beats notes: [BeatNote], tempo: Double, lengthBeats: Double? = nil) {
        let interval = 60 / max(tempo, 1)
        let events = notes.map {
            NoteEvent(
                voice: $0.voice,
                note: $0.note,
                velocity: $0.velocity,
                onset: $0.startBeat * interval,
                duration: $0.beats * interval,
            )
        }
        let end = notes.map { $0.startBeat + $0.beats }.max() ?? 0
        self.init(events: events, length: (lengthBeats ?? end) * interval)
    }

    public static let empty = Self(events: [], length: 0)
}

/// Where notes go: the audio engine in the app, a recorder in tests. Only a `SoundPlayer`
/// (SegueUI) ever holds one, and none exists while a gig runs (section 9).
public protocol SoundOutput: AnyObject, Sendable {
    /// Loads what the voices need (the sound bank) off the main thread. Makes no sound.
    func prepare(chord: ChordSound, bass: BassSound)
    /// Plays `events`, their onsets counted from `delay` seconds after now.
    func schedule(_ events: [NoteEvent], in delay: TimeInterval)
    /// Silences everything at once: pending events dropped, sounding notes released.
    func stopAll()
}
