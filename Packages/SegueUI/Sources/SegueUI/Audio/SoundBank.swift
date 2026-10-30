#if os(macOS)
    import Foundation
    import Playback

    /// The bundled sound bank (P8-6 section 12): `Sounds/SegueSounds.sf2`, extracted by
    /// `scripts/soundbank/extract.py` from FluidR3_GM (MIT), every voice chosen by Ryan's
    /// blind listening A/B on 2026-10-30 (R166; finger bass confirmed as FluidR3's). To try
    /// another bank, re-run the extractor into the same file: the programs below are General
    /// MIDI numbers, so nothing else changes.
    enum SoundBank {
        /// The bundled SF2 (never SF3: `AVAudioUnitSampler` crashed loading one [A1]).
        static var bundledURL: URL? {
            Bundle.module.url(
                forResource: "SegueSounds",
                withExtension: "sf2",
                subdirectory: "Sounds",
            )
        }

        /// The macOS built-in GS bank, loaded in place as the first fallback (never bundled,
        /// R162 Q11). Undocumented path; the second fallback is the sampler's own sine.
        static let systemURL = URL(
            fileURLWithPath:
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
        )

        /// General MIDI programs, bank 0.
        static func program(_ sound: ChordSound) -> UInt8 {
            switch sound {
            case .piano: 0
            case .cleanGuitar: 27
            }
        }

        static func program(_ sound: BassSound) -> UInt8 {
            switch sound {
            case .finger: 33
            case .pick: 34
            }
        }

        /// Per-voice gain in dB (`AVAudioUnitSampler.overallGain`), so each voice peaks at or
        /// below -6 dBFS and voices together at or below -1 dBFS; the limiter is only a safety
        /// net. Measured 2026-10-30, offline at 48 kHz, velocity 100: piano a four-note C
        /// major 7th -2.7 dBFS raw, -6.2 with gain; clean guitar a six-string G -1.0 raw, -6.5;
        /// finger and pick bass the loudest single note of B0 ... G2 -11.5 raw, -6.5; together
        /// (chord plus bass) -2.9 ... -1.6 dBFS.
        static func gain(_ sound: ChordSound) -> Float {
            switch sound {
            case .piano: -3.5
            case .cleanGuitar: -5.5
            }
        }

        static func gain(_: BassSound) -> Float {
            5
        }
    }
#endif
