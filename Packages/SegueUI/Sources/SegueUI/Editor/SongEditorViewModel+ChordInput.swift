import ChordPro
import Editing
import Foundation
import MusicTheory

/// Chord input in the display key: the palette, the visual popover's suggestions, and the
/// transforms that turn what the user typed into source text. In Nashville view numbers are
/// shown and accepted (phase 1 build rulings); letter names are accepted in every view.
extension SongEditorViewModel {
    func computePaletteChords() -> [String] {
        let transform = inputTransform
        var seen = Set<String>()
        var result: [String] = []
        for occurrence in snapshot.chords {
            guard occurrence.token.chord != nil else { continue }
            let name = transform.display(occurrence.token)
            if seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }

    /// The transform chord input goes through: the view's own (so Nashville view shows and
    /// accepts numbers, phase 1 build rulings), with letter names accepted in every view.
    /// Built from the current snapshot, so a `{key}` typed a moment ago already counts.
    var inputTransform: DisplayTransform {
        DisplayTransform(
            options: options,
            key: KeyContext(document: snapshot.document),
            capo: snapshot.document.metadata.capo,
        )
    }

    /// The display transform with Nashville off: letter names in the display key.
    var letterTransform: DisplayTransform {
        let transform = inputTransform
        var letters = transform.options
        letters.nashville = false
        return DisplayTransform(options: letters, key: transform.key, capo: transform.capo)
    }

    /// Suggestions for the visual chord popover and palette, in the display key: song
    /// chords, then the key's diatonic chords, then extensions of the typed root. In
    /// Nashville view they are numbers, unless the user has started typing a letter name.
    func displayChordSuggestions(prefix: String) -> [String] {
        let transform = inputTransform
        if transform.options.nashville, let written = transform.key.writtenKey,
           prefix.isEmpty || Nashville.looksLikeNumber(prefix)
        {
            return ChordSuggestions.chords(
                prefix: prefix,
                songChords: paletteChords,
                diatonic: written.diatonicChordSymbols.map {
                    Nashville.number(for: ChordToken(parsing: $0), in: written)
                },
                numbers: true,
            )
        }
        let letters = letterTransform
        var seen = Set<String>()
        let songChords = snapshot.chords.compactMap { occurrence -> String? in
            guard occurrence.token.chord != nil else { return nil }
            let name = letters.display(occurrence.token)
            return seen.insert(name).inserted ? name : nil
        }
        return ChordSuggestions.chords(
            prefix: prefix,
            songChords: songChords,
            diatonic: letters.displayKey?.diatonicChordSymbols ?? [],
        )
    }
}
