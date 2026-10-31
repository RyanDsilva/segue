import ChordPro

// P8-8 section 3.1: the matching forms of a song's artists. `ArtistNames` itself lives in
// ChordPro so Ingest can split; the forms need `RomanNormalizer`, which lives here.

public extension ArtistNames {
    /// Matching forms of a stored list: each value split as `split` does (so a legacy
    /// `{artist: Vishal & Shekhar}` meets Vishal and Shekhar), then
    /// `RomanNormalizer.normalize`. For matching only, never for display or writes.
    static func forms(_ artists: [String]) -> Set<String> {
        var result: Set<String> = []
        for value in artists {
            for part in split(value).parts {
                let form = RomanNormalizer.normalize(part)
                if !form.isEmpty {
                    result.insert(form)
                }
            }
        }
        return result
    }
}
