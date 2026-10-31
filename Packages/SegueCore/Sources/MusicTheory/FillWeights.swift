// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 11.3). The fill
// ranking weights, one static value so tuning after the by-ear check (P8-7f step 23) changes
// numbers only, never code.

/// The ranking weights. Every term a candidate's score sums is one of these.
public struct FillWeights: Sendable, Hashable {
    /// `templatePrior` = `log(1 + count) / log(1 + most) * priorScale` (0 ... 3, the walk-up
    /// prior's range), `count` the corpus examples of the template's family for the feel.
    public var priorScale: Double
    /// Per strong beat on a root or chord tone.
    public var strongBeatTone: Double
    /// Per R165 cross-relation with the sounding chord's fifth or seventh.
    public var clash: Double
    public var resolutionHalfStep: Double
    public var resolutionWholeStep: Double
    public var resolutionFifth: Double
    /// Per note per pulse above the comfortable density for the tempo and feel.
    public var densityOver: Double
    /// A Rock feel with two or more notes per pulse.
    public var densityRock: Double
    /// Notes per pulse that are comfortable: at most `densityFast` above `fastTempo`, at
    /// most `densityRestrained` for Worship or below `slowTempo`, else `densityMid`.
    public var densityMid: Double
    public var densityFast: Double
    public var densityRestrained: Double
    public var fastTempo: Double
    public var slowTempo: Double
    /// The shortest note any candidate may have, in seconds (a sixteenth at 140 BPM is 0.107).
    public var shortestNote: Double
    /// The most fill notes for Worship or a slow song (11.5).
    public var restrainedNotes: Int
    /// Per leap over a fifth.
    public var contour: Double
    /// Per note folded by an octave into range.
    public var range: Double
    /// A D, a chromatic or an old-root ending into a new key.
    public var keyChange: Double
    /// On a prepared lift, a fill that arpeggiates V' onto its third.
    public var keyChangeArpeggio: Double
    /// Per fill bar without a note on its first pulse.
    public var downbeat: Double
    /// The approach equals the walk-up the chart shows for the change.
    public var walkUpAgreement: Double
    /// The hold ("no fill") candidate: first for a written stepwise line (bVI-bVII-i
    /// included) and slow Worship; in the top two at a key change (R168).
    public var holdFirst: Double
    public var holdKeyChange: Double
    /// The most candidates offered (A-D plus More, R167 Q11).
    public var limit: Int

    public static let standard = Self(
        priorScale: 3,
        strongBeatTone: 0.5,
        clash: -5,
        resolutionHalfStep: 2,
        resolutionWholeStep: 1,
        resolutionFifth: 1,
        densityOver: -1.5,
        densityRock: 0.5,
        densityMid: 4,
        densityFast: 2,
        densityRestrained: 2,
        fastTempo: 140,
        slowTempo: 80,
        shortestNote: 0.1,
        restrainedNotes: 4,
        contour: -0.5,
        range: -1,
        keyChange: 2,
        keyChangeArpeggio: 1.5,
        downbeat: -1,
        walkUpAgreement: 1,
        holdFirst: 8,
        holdKeyChange: 3,
        limit: 5,
    )
}
