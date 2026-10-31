// Phase 3 (R80, R110): the set essentials, key + tempo (P8-8: a song's time comes from its
// tempo and bars). The one definition of
// "missing" behind the song card's dots, the library rows' quiet dot and the built-in
// "Missing essentials" smart filter.

import ChordPro
import MusicTheory

/// A set essential: what set timing and flow need from every song (R80).
public enum SetEssential: String, Sendable, Hashable, CaseIterable {
    /// `{key}`, written and valid (a key only detected from the chords does not count).
    case key
    /// `{tempo}`, a valid BPM.
    case tempo
}

/// Which set essentials a song lacks.
public enum SongEssentials {
    /// The essentials `document` is missing, in `SetEssential.allCases` order (empty when
    /// it has both).
    public static func missing(in document: SongDocument) -> [SetEssential] {
        let metadata = document.metadata
        return SetEssential.allCases.filter { essential in
            switch essential {
            case .key: metadata.key.flatMap(SongKey.init(parsing:)) == nil
            case .tempo: metadata.tempo == nil
            }
        }
    }

    /// Whether `document` lacks any set essential.
    public static func isMissingAny(in document: SongDocument) -> Bool {
        !missing(in: document).isEmpty
    }
}
