// P8-7c (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 11.3, R168). The
// standard template set, derived from fill-corpus.json at d2805f3: each template cites the
// corpus examples it implements (`FillTemplateCorpusTests` checks them). Corpus family to
// rhythm family: quarterWalk and the V' arpeggio walk; pickup8, chromaticLine, approachNote,
// slideInto, dominantApproach and dominantPedal are eighth pickups; sixteenRun, scaleRun,
// pentatonicRun and tihai are sixteenth runs; tripletRun is triplets; rootFiveOctave,
// octavePops, chordArpeggio, machineGun and the pentatonic bar figure are octave figures;
// anticipation, restPickup and stopTime are pushes. `hold` is the explicit "no fill"
// candidate, not a template.

extension FillTemplates {
    /// `count` slots of one unit each, ending on the landing onset.
    private static func run(
        _ unit: FillTime.Unit,
        _ pitches: [FillPitch],
        before end: Int = 0,
    ) -> [FillSlot] {
        pitches.enumerated().map { index, pitch in
            FillSlot(FillTime(index - pitches.count - end, unit), FillTime(1, unit), pitch)
        }
    }

    private static func slot(
        _ at: Int,
        _ unit: FillTime.Unit,
        _ pitch: FillPitch,
        articulations: Set<Articulation> = [],
        compoundOnly: Bool = false,
    ) -> FillSlot {
        FillSlot(
            FillTime(at, unit),
            FillTime(1, unit),
            pitch,
            articulations: articulations,
            compoundOnly: compoundOnly,
        )
    }

    static let standardTemplates: [FillTemplate] = walkTemplates + pickupTemplates
        + runTemplates + otherTemplates

    private static let walkTemplates = [
        FillTemplate(
            id: "dominantArpeggio",
            family: .walk,
            corpusFamily: "dominantApproach",
            slots: run(.pulse, [.fifth, .third]),
            condition: .preparedLift,
            corpus: ["kc-lovers-concerto", "kc-whole-step-sharp1-cue"],
        ),
        FillTemplate(
            id: "quarterWalk",
            family: .walk,
            corpusFamily: "quarterWalk",
            coversSpan: true,
            corpus: [
                "sec-good-vibrations", "sec-country-walk-up", "sec-bluegrass-walk-down",
                "sec-no-treble-sharp4", "kc-mirrors-relative", "kc-happy-together",
                "kc-save-me", "bw-rock-n-roll-soniye", "sec-yamaha-i-vi-ii-v",
            ],
        ),
    ]

    private static let pickupTemplates = [
        FillTemplate(
            id: "pickup8",
            family: .pickup,
            corpusFamily: "pickup8",
            slots: [slot(-3, .eighth, .root, compoundOnly: true)]
                + run(.eighth, [.approach, .approach]),
            corpus: [
                "kc-man-in-the-mirror", "kc-love-on-top-chain", "kc-livin-prayer-short-bar",
                "kc-because-the-night", "kc-bvii-route", "kc-ii-v-leadin", "bw-harmonic-v-i",
                "bw-dadra-pickup", "bw-bhairav-run", "bw-last-mukhda-lift",
            ],
        ),
        FillTemplate(
            id: "chromaticLine",
            family: .pickup,
            corpusFamily: "chromaticLine",
            slots: run(.eighth, [.root, .chromatic(3), .chromatic(2), .chromatic(1)]),
            corpus: [
                "sec-born-to-be-my-baby-chorus", "sec-livin-prayer-neighbour",
                "sec-step-into-christmas", "sec-yamaha-walkdown", "sec-yamaha-walkup",
                "sec-tb-chromatic", "kc-show-must-go-on", "kc-biii-route",
            ],
        ),
        FillTemplate(
            id: "approachNote",
            family: .pickup,
            corpusFamily: "approachNote",
            slots: run(.pulse, [.approach]),
            corpus: [
                "sec-keep-me-hangin-on",
                "sec-reach-out",
                "kc-love-on-top",
                "kc-common-tone-hold",
            ],
        ),
        FillTemplate(
            id: "slideInto",
            family: .pickup,
            corpusFamily: "slideInto",
            slots: [slot(-1, .eighth, .approach, articulations: [.slide])],
            corpus: [
                "sec-walk-this-way-slide", "sec-tb-slide-double-stop", "kc-hello-i-love-you",
                "bw-ballad-slide",
            ],
        ),
        FillTemplate(
            id: "dominantApproach",
            family: .pickup,
            corpusFamily: "dominantApproach",
            slots: run(.eighth, [.dominant]),
            corpus: ["sec-studybass-fifth", "kc-come-on-eileen", "bw-ballad-fifth"],
        ),
        FillTemplate(
            id: "dominantPedal",
            family: .pickup,
            corpusFamily: "dominantPedal",
            slots: run(.eighth, [.root, .root, .root, .root]),
            condition: .preparedLift,
            corpus: ["kc-half-step-sharp5-pedal"],
        ),
    ]

    private static let runTemplates = [
        FillTemplate(
            id: "sixteenRun",
            family: .run,
            corpusFamily: "sixteenRun",
            slots: run(.sixteenth, [.scaleUp, .scaleUp, .scaleUp, .scaleUp]),
            corpus: ["sec-walk-this-way-run", "bw-interlude-harmonic-run"],
        ),
        FillTemplate(
            id: "scaleRun",
            family: .run,
            corpusFamily: "scaleRun",
            slots: run(.sixteenth, [.scaleDown, .scaleDown, .scaleDown, .scaleDown]),
            corpus: [
                "sec-lead-me-to-the-cross", "sec-born-to-be-my-baby-pre", "sec-gospelchops-2",
                "bw-harmonic-descent",
            ],
        ),
        FillTemplate(
            id: "pentatonicRun",
            family: .run,
            corpusFamily: "pentatonicRun",
            slots: [slot(-4, .sixteenth, .octave)]
                + run(.sixteenth, [.pentatonicDown, .pentatonicDown, .pentatonicDown]),
            corpus: [
                "sec-invisible-touch", "sec-kershaw-fill-bar", "sec-tb-awesome-pentatonic",
                "sec-gbp8-pentatonic", "sec-posidovega-verse-chorus", "sec-bonedo-rnb-blues",
                "bw-bhoopali-pentatonic",
            ],
        ),
        // An off-beat start ("3e"): seven sixteenths up into the landing.
        FillTemplate(
            id: "sixteenRunLong",
            family: .run,
            corpusFamily: "sixteenRun",
            slots: run(.sixteenth, Array(repeating: .scaleUp, count: 7)),
            corpus: ["sec-gospelchops-1"],
        ),
        // Three cells of (step, step, landing), the last landing on the downbeat (R168:
        // only in a Bollywood feel).
        FillTemplate(
            id: "tihai",
            family: .run,
            corpusFamily: "tihai",
            slots: [-10, -9, -8, -6, -5, -4, -2, -1, 0].enumerated().map { index, step in
                let pitch: FillPitch = switch index % 3 {
                case 0: .targetStep(2)
                case 1: .targetStep(1)
                default: .target
                }
                return FillSlot(
                    FillTime(step, .sixteenth),
                    FillTime(step == 0 ? 4 : 1, .sixteenth),
                    pitch,
                    articulations: step == 0 ? [.accent] : [],
                )
            },
            condition: .bollywood,
            ownsLanding: true,
            corpus: ["bw-tihai-cadence"],
        ),
    ]

    private static let otherTemplates = [
        FillTemplate(
            id: "tripletRun",
            family: .triplet,
            corpusFamily: "tripletRun",
            slots: run(.triplet, [.fifth, .octave, .approach]),
            simpleOnly: true,
            corpus: ["sec-tb-sixteenth-triplet"],
        ),
        FillTemplate(
            id: "rootFiveOctave",
            family: .octave,
            corpusFamily: "rootFiveOctave",
            slots: [slot(-2, .pulse, .fifth), slot(-1, .pulse, .octave)],
            corpus: [
                "sec-tb-awesome-fifths", "sec-pop-octave-pickup", "kc-aug6-route",
                "bw-dum-maro-dum-ostinato",
            ],
        ),
        FillTemplate(
            id: "octavePops",
            family: .octave,
            corpusFamily: "octavePops",
            slots: run(.eighth, [.root, .octave, .root], before: 1)
                + [slot(-1, .eighth, .octave)],
            corpus: ["sec-baby-love-octaves", "sec-bonedo-octave", "bw-disco-octaves"],
        ),
        // A bar of eighths up the chord and back: R 3 5 7 8 7 5 3.
        FillTemplate(
            id: "chordArpeggio",
            family: .octave,
            corpusFamily: "chordArpeggio",
            slots: run(
                .eighth,
                [.root, .third, .fifth, .seventh, .octave, .seventh, .fifth, .third],
            ),
            corpus: ["sec-tb-arpeggio", "sec-ninth-lick"],
        ),
        // A bar of pentatonic eighths up to the octave and back (an eighth figure, so the
        // octave family), landing on the octave and overhanging an eighth onto the root.
        FillTemplate(
            id: "pentatonicBar",
            family: .octave,
            corpusFamily: "pentatonicRun",
            slots: [slot(-8, .eighth, .root)]
                + run(.eighth, Array(repeating: .pentatonicUp, count: 4), before: 3)
                + [slot(-3, .eighth, .octave)]
                + run(.eighth, [.pentatonicDown, .pentatonicDown])
                + [slot(0, .eighth, .target), slot(1, .eighth, .target)],
            ownsLanding: true,
            corpus: ["sec-bonedo-full-bar"],
        ),
        FillTemplate(
            id: "machineGun",
            family: .octave,
            corpusFamily: "machineGun",
            slots: run(.sixteenth, [.octave, .octave, .octave], before: 1)
                + [slot(-1, .sixteenth, .octave)],
            corpus: ["sec-machine-gun"],
        ),
        FillTemplate(
            id: "anticipation",
            family: .push,
            corpusFamily: "anticipation",
            slots: [FillSlot(FillTime(-1, .eighth), FillTime(3, .eighth), .target)],
            ownsLanding: true,
            corpus: ["sec-livin-prayer-anticipation", "kc-street-life"],
        ),
        FillTemplate(
            id: "restPickup",
            family: .push,
            corpusFamily: "restPickup",
            slots: [slot(-1, .sixteenth, .approach, articulations: [.staccato])],
            corpus: ["sec-baby-love-pickup", "bw-koi-kahe-staccato", "bw-chaal-pickup"],
        ),
        FillTemplate(
            id: "stopTime",
            family: .push,
            corpusFamily: "stopTime",
            slots: [
                FillSlot(
                    FillTime(-1, .bar),
                    FillTime(1, .eighth),
                    .root,
                    articulations: [.staccato],
                ),
                slot(-1, .eighth, .approach),
            ],
            corpus: ["sec-rock-stop-pickup", "kc-i-will-always-love-you"],
        ),
    ]
}
