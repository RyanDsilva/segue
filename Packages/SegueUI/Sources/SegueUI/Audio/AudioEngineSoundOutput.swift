#if os(macOS)
    import Foundation
    import Playback

    /// The app's `SoundOutput` (P8-6 section 8.2): bass and chord events become MIDI notes on
    /// the shared engine's samplers, click events its tick sounds.
    public final class AudioEngineSoundOutput: SoundOutput {
        private let host: AudioEngineHost

        public init(host: AudioEngineHost) {
            self.host = host
        }

        public func prepare(chord: ChordSound, bass: BassSound) {
            host.setSounds(chord: chord, bass: bass)
            host.prepare()
        }

        public func schedule(_ events: [NoteEvent], in delay: TimeInterval) {
            host.schedule(events, in: delay)
        }

        public func stopAll() {
            host.stopNotes()
            host.stopClicks()
        }
    }
#endif
