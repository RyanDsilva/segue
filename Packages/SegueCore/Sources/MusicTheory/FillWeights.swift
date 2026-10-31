// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 11.3). The fill
// ranking weights, one static value so tuning after the by-ear check (P8-7f step 23) changes
// numbers only, never code.

/// The ranking weights. Every term a candidate's score sums is one of these.
public struct FillWeights: Sendable, Hashable {
    /// `templatePrior` = `log(1 + count) / log(1 + most) * priorScale` (0 ... 3, the walk-up
    /// prior's range), `count` the corpus examples of the template's family for the feel.
    public var priorScale: Double
    /// Smoothing of the per-feel corpus counts toward all feels: `count` = the feel's count +
    /// `priorSmoothing` x the family's count over all feels / the number of feels (a feel's
    /// handful of examples is not the whole story).
    public var priorSmoothing: Double
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
    /// `situation`: chord-scale material over a repeated chord (a vamp), and an approach
    /// shape there (nothing to aim at).
    public var vampChordScale: Double
    public var vampApproach: Double
    /// An accent over a repeated chord (the ghosted sixteenth before the downbeat, the slide,
    /// the repeated note: rhythm-only fills, corpus doc section 4.1).
    public var vampAccent: Double
    /// An arpeggio over a dominant seventh.
    public var arpeggioDominant: Double
    /// An accent (anticipation, slide, repeated note, stop) into a new section.
    public var accentSection: Double
    /// A rhythmic cadence (a tihai) into a new section.
    public var cadenceSection: Double
    /// Per fill note above `shortFillNotes` in Worship or a slow song: ballad practice is "less
    /// is more" (corpus doc section 4.1).
    public var restrainedBusy: Double
    /// Under a raga or harmonic-minor mode, a fill that sounds the mode's colour: both notes
    /// of its augmented second (b6-7, Bhairav's b2-3), or only pentatonic notes under a
    /// pentatonic mode (corpus doc section 6 item 6).
    public var modeColour: Double
    /// Per fill note above `shortFillNotes` into a new key: the band just moves up (corpus
    /// doc section 4.2), so a fill there stays short.
    public var liftBusy: Double
    /// The fill notes a short fill has (into a new key, in a slow song).
    public var shortFillNotes: Int
    /// When the last departing chord already sits in the new key (a pivot), the walk
    /// through it.
    public var pivotWalk: Double
    /// The hold ("no fill") candidate: first for a written stepwise line (bVI-bVII-i
    /// included) and slow Worship; in the top two at a key change (R168).
    public var holdFirst: Double
    public var holdKeyChange: Double
    /// The most candidates offered (A-D plus More, R167 Q11).
    public var limit: Int

    public static let standard = Self(
        priorScale: 4,
        priorSmoothing: 0.5,
        strongBeatTone: 0.5,
        clash: -5,
        resolutionHalfStep: 1,
        resolutionWholeStep: 0.5,
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
        contour: -0.25,
        range: -1,
        keyChange: 2,
        keyChangeArpeggio: 1.5,
        downbeat: -1,
        walkUpAgreement: 2,
        vampChordScale: 2,
        vampApproach: -2,
        vampAccent: 1,
        arpeggioDominant: 3,
        accentSection: 1.5,
        cadenceSection: 4,
        restrainedBusy: -1,
        modeColour: 2,
        liftBusy: -1,
        shortFillNotes: 2,
        pivotWalk: 2,
        holdFirst: 8,
        holdKeyChange: 3,
        limit: 5,
    )
}
