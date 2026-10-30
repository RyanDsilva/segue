#if os(macOS)
    import Diagrams
    import Editing
    import MusicTheory
    import SwiftUI

    /// What the stage mini neck shows (P8-4 7.3, R158 Q6): the bass note of the chord at the
    /// reading line, where to play it in the box around the song's home fret, and the other
    /// places of the same note inside the drawn window. A value, so the `Canvas` redraws only
    /// when it changes.
    struct StageBassNeckState: Equatable {
        /// The note big ("B"), at sounding pitch; never the Nashville number.
        var note: String
        var suggested: FretPosition
        /// The other positions of the note inside `window` (hollow rings).
        var others: [FretPosition]
        /// The frets drawn: `BassFretboard.windowFrets` frets.
        var window: ClosedRange<Int>
        var tuning: Tuning
        /// The chord at the reading line is `N.C.` or unknown: the last real chord stays,
        /// dimmed.
        var dimmed = false

        /// The note's pitch class (where it was suggested).
        var pitchClass: PitchClass {
            PitchClass(midi: BassFretboard.pitch(suggested, tuning: tuning))
        }

        /// "A2": the string's open note, then the fret.
        var positionText: String {
            tuning.openStringName(suggested.string) + "\(suggested.fret)"
        }

        /// "B, A string fret 2" ("E string open" for fret 0).
        var accessibilityValue: String {
            let string = "\(tuning.openStringName(suggested.string)) string"
            let fret = suggested.fret == 0 ? "open" : "fret \(suggested.fret)"
            return "\(note), \(string) \(fret)"
        }

        /// The neck for `chord` (a chord token's text as written) in a song rendered with
        /// `transform`: the sounding bass note, positioned around `home`. nil for `N.C.`,
        /// unknown chords and when the note has no position.
        static func make(
            chord original: String,
            transform: DisplayTransform,
            home: Int,
            tuning: Tuning,
        ) -> Self? {
            guard let concert = transform.concert(ChordToken(parsing: original)).chord else {
                return nil
            }
            return make(symbol: concert.symbol, home: home, tuning: tuning)
        }

        /// The neck for a bass note as the stage draws it ("C#"; a "3 \u{00B7} C#" prefix is
        /// ignored).
        static func make(drawn text: String, home: Int, tuning: Tuning) -> Self? {
            let name = text.components(separatedBy: " \u{00B7} ").last ?? text
            guard let symbol = ChordSymbol(parsing: name) else { return nil }
            return make(symbol: symbol, home: home, tuning: tuning)
        }

        /// The neck for a chord's bass (its slash bass, else its root).
        private static func make(symbol: ChordSymbol, home: Int, tuning: Tuning) -> Self? {
            let note = symbol.bass ?? symbol.root
            guard let suggested = BassFretboard.suggested(
                note.pitchClass,
                home: home,
                tuning: tuning,
            ) else { return nil }
            let window = BassFretboard.window(home: home, including: suggested)
            let others = BassFretboard.positions(of: note.pitchClass, tuning: tuning).filter {
                $0 != suggested && window.contains($0.fret)
            }
            return Self(
                note: note.chartName,
                suggested: suggested,
                others: others,
                window: window,
                tuning: tuning,
            )
        }

        /// The song's hand position: the sounding key's tonic, else the first bass note.
        static func home(transform: DisplayTransform, firstChord: String?, tuning: Tuning)
            -> Int
        {
            let tonic = transform.concertKey?.tonic.pitchClass ?? firstChord.flatMap { text in
                transform.concert(ChordToken(parsing: text)).chord.map { chord in
                    (chord.symbol.bass ?? chord.symbol.root).pitchClass
                }
            }
            return tonic.map { BassFretboard.homeFret(tonic: $0, tuning: tuning) } ?? 0
        }
    }

    /// The stage mini neck at the left end of the status band (P8-4 7.3): the note and its
    /// position ("B" with "A2"), then a 5-fret window of the neck in tab orientation (lowest
    /// string at the bottom), the suggested place a filled cue dot and the note's other places
    /// in the window hollow rings. Quiet: no animation, no clicks, no focus.
    struct StageBassNeck: View, Equatable {
        let state: StageBassNeckState

        /// The neck's height: the 30 pt status line plus room for the fret number under the
        /// strings (the status band has 8 pt above and below the line).
        static let height: CGFloat = 34
        static let fretWidth: CGFloat = 22
        static let labelGap: CGFloat = 8
        /// Width of the note and position label.
        static let labelWidth: CGFloat = 42
        /// The whole neck, label included (the status line starts 16 pt after it).
        static var width: CGFloat {
            labelWidth + labelGap + fretWidth * CGFloat(BassFretboard.windowFrets)
        }

        var body: some View {
            HStack(alignment: .center, spacing: Self.labelGap) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(state.note)
                        .font(SchibstedGrotesk.bold.font(size: 18))
                        .foregroundStyle(Theme.color.ink)
                    Text(state.positionText)
                        .font(SchibstedGrotesk.semiBold.font(size: 11))
                        .foregroundStyle(Theme.color.muted)
                        .offset(y: 3)
                }
                .lineLimit(1)
                .fixedSize()
                .frame(width: Self.labelWidth, alignment: .trailing)
                NeckCanvas(state: state)
                    .frame(
                        width: Self.fretWidth * CGFloat(BassFretboard.windowFrets),
                        height: Self.height,
                    )
            }
            .frame(height: Self.height)
            .opacity(state.dimmed ? 0.4 : 1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bass neck")
            .accessibilityValue(state.accessibilityValue)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier(AccessibilityID.liveBassNeck)
        }
    }

    /// The neck drawing: strings, fret wires, the nut, the first fret number and the dots.
    private struct NeckCanvas: View {
        let state: StageBassNeckState

        var body: some View {
            Canvas { context, size in
                let strings = state.tuning.strings.count
                let spacing: CGFloat = strings == 5 ? 5.5 : 7
                let span = spacing * CGFloat(strings - 1)
                let top: CGFloat = 4
                let fret = StageBassNeck.fretWidth
                let frets = BassFretboard.windowFrets
                let lower = state.window.lowerBound
                // String 0 (lowest) at the bottom.
                func stringY(_ string: Int) -> CGFloat {
                    top + span - CGFloat(string) * spacing
                }
                // With the nut in the window the strings start just left of the open-string
                // column, so an open-string dot sits on its string.
                let wireStart: CGFloat = lower == 0 ? 2 : 0
                for string in 0 ..< strings {
                    var line = Path()
                    line.move(to: CGPoint(x: wireStart, y: stringY(string)))
                    line.addLine(to: CGPoint(x: size.width, y: stringY(string)))
                    context.stroke(line, with: .color(Theme.color.indicatorOff), lineWidth: 1)
                }
                // A wire at the right edge of each slot; with the open slot shown, its edge is
                // the nut (2 pt).
                for slot in 0 ..< frets {
                    let isNut = lower == 0 && slot == 0
                    let x = CGFloat(slot + 1) * fret - (isNut ? 1 : 0.5)
                    var wire = Path()
                    wire.move(to: CGPoint(x: x, y: top - 0.5))
                    wire.addLine(to: CGPoint(x: x, y: top + span + 0.5))
                    context.stroke(
                        wire,
                        with: .color(isNut ? Theme.color.ink : Theme.color.line),
                        lineWidth: isNut ? 2 : 1,
                    )
                }
                // The first fretted fret's number under its slot.
                let firstSlot = lower == 0 ? 1 : 0
                let number = Text("\(lower + firstSlot)")
                    .font(SchibstedGrotesk.semiBold.font(size: 9))
                    .foregroundStyle(Theme.color.muted)
                context.draw(
                    number,
                    at: CGPoint(x: (CGFloat(firstSlot) + 0.5) * fret, y: size.height - 1),
                    anchor: .bottom,
                )
                func center(_ position: FretPosition) -> CGPoint {
                    let slot = CGFloat(position.fret - lower)
                    return CGPoint(x: (slot + 0.5) * fret, y: stringY(position.string))
                }
                for position in state.others {
                    let point = center(position)
                    let ring = Path(ellipseIn: CGRect(
                        x: point.x - 3,
                        y: point.y - 3,
                        width: 6,
                        height: 6,
                    ))
                    context.stroke(ring, with: .color(Theme.color.muted), lineWidth: 1.2)
                }
                let point = center(state.suggested)
                let dot = Path(ellipseIn: CGRect(
                    x: point.x - 3.5,
                    y: point.y - 3.5,
                    width: 7,
                    height: 7,
                ))
                context.fill(dot, with: .color(Theme.color.cue))
            }
        }
    }
#endif

#if os(macOS)
    /// The bass-note view's scale line in the stage header (P8-4 6.5, decision 8): "Sounding A
    /// major: A B C# D E F# G#", muted and quiet, the first thing dropped when the header is
    /// narrow (it never makes the title truncate).
    struct StageScaleLine: View {
        /// `RenderHeader.scale`: "A major: A B C# D E F# G#".
        let scale: String

        var body: some View {
            ViewThatFits(in: .horizontal) {
                Text("Sounding \(scale)")
                    .font(SchibstedGrotesk.medium.font(size: 16))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel(Self.spoken(scale))
                    .accessibilityIdentifier(AccessibilityID.liveBassScale)
                Color.clear.frame(width: 0, height: 0)
            }
            .layoutPriority(-1)
        }

        /// "Sounding key A major, scale A, B, C sharp, D, E, F sharp, G sharp"; minor keys
        /// read "F sharp minor".
        static func spoken(_ scale: String) -> String {
            let parts = scale.components(separatedBy: ": ")
            let key = parts.first ?? scale
            let notes = (parts.dropFirst().first ?? "").split(separator: " ").map(spokenNote)
            let spokenKey = if key.hasSuffix(" major") {
                spokenNote(key.dropLast(" major".count)) + " major"
            } else {
                spokenNote(key.dropLast()) + " minor"
            }
            return "Sounding key \(spokenKey), scale \(notes.joined(separator: ", "))"
        }

        /// "C#" -> "C sharp", "Bb" -> "B flat".
        private static func spokenNote(_ note: Substring) -> String {
            guard let letter = note.first else { return "" }
            let accidental = note.dropFirst()
            return String(letter) +
                (accidental == "#" ? " sharp" : accidental == "b" ? " flat" : "")
        }
    }

    /// The mini neck for the chord at the reading line, at the status band's left end (P8-4
    /// 7.3), read inside a stage timeline; it redraws only when the chord changes (its state
    /// is compared), never animated.
    struct StageBassNeckBand: View {
        let session: LiveSession

        var body: some View {
            TimelineView(.animation(paused: !session.isAutoScrolling)) { _ in
                if let state = session.bassNeck(at: session.context.scrollClock.now()) {
                    StageBassNeck(state: state)
                        .equatable()
                }
            }
            .frame(height: StageBassNeck.height)
            .padding(.leading, LiveView.horizontalPadding)
        }
    }
#endif
