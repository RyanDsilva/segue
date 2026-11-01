// P9-3 9.8 (R178): a medley plays as one timeline, each member's played passes after the
// last, with no gap: every member keeps its own chords, meter, tempo and key, and starts on
// a downbeat so the click switches at the boundary on the bar grid. Pure.

public extension SongTimeline {
    /// `parts` one after another (each a `slice`, already whole bars): passes numbered on
    /// through the parts, every chord at its own `{tempo}` and meter. A push on a part's
    /// first chord is ignored, so each member starts on its downbeat. The positional maps
    /// are the first part's.
    static func concatenating(_ parts: [Self]) -> Self {
        guard parts.count > 1 else { return parts.first ?? .empty }
        var entries: [Entry] = []
        var passes: [TimedPass] = []
        for part in parts {
            let base = passes.count
            for (index, entry) in part.entries.enumerated() {
                var entry = entry
                entry.chord.pass += base
                if index == 0 {
                    entry.push = nil
                }
                entries.append(entry)
            }
            passes += part.passes
        }
        let first = parts[0]
        return assemble(
            entries,
            passes: passes,
            maps: PositionalMaps(meters: first.meters, tempos: first.tempos, keys: first.keys),
            unmatched: [],
            roundToBars: true,
        )
    }
}
