import MusicTheory

/// What a typed gig key ("kesariya in A") does to a new slot's overrides.
public enum GigKeyResult: Sendable, Equatable {
    /// The slot already shows that key (or its relative): leave `transpose` nil.
    case noOverride
    /// Set `SetlistOverrides.transpose` to this many semitones.
    case transpose(Int)
    /// The song has no declared or detectable key, so the typed key is ignored.
    case songHasNoKey
}

public extension SetlistOverrides {
    /// The `transpose` that makes the slot's displayed key `target` (P8-5 section 7, R158
    /// Q1-Q2). "In A" names the key the slot's Key column shows (`DisplayTransform
    /// .displayKey`: written key + transpose + the capo display offset), not concert pitch.
    ///
    /// - The move is the smallest one, -5 ... +6 semitones (+6 for a tritone).
    /// - A key in the relative mode of the key the slot shows ("in C" for a song showing
    ///   Am) names the same signature, so nothing changes.
    /// - Any other mode mismatch goes tonic to tonic, keeping the song's mode ("in D" for
    ///   an Am song shows Dm).
    /// - A result equal to `songTranspose` (what an empty override already shows) is
    ///   `.noOverride`. The capo override is never touched.
    ///
    /// `songTranspose` is the song's saved view transpose; `capoOffset` is
    /// `Capo.displayOffset(capo: songCapo, mode: options.capoMode)`.
    static func transpose(
        toShow target: SongKey,
        written: SongKey?,
        songTranspose: Int,
        capoOffset: Int,
    ) -> GigKeyResult {
        guard let written else { return .songHasNoKey }
        let shown = written.transposed(by: songTranspose + capoOffset)
        if target.mode != shown.mode,
           target.tonic.pitchClass == shown.relative.tonic.pitchClass
        {
            return .noOverride
        }
        let from = written.tonic.pitchClass.transposed(by: capoOffset)
        var delta = from.semitones(to: target.tonic.pitchClass)
        if delta > 6 {
            delta -= 12
        }
        return delta == songTranspose ? .noOverride : .transpose(delta)
    }
}
