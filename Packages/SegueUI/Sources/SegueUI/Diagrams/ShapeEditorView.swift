// Owner: unit B (diagram views). Frozen interface: docs/phases/1-interfaces.md.

import Diagrams
import MusicTheory
import SwiftUI

/// Edits a custom shape for one chord and returns it as a `{define}`; the host (unit D)
/// writes it with `EditOperation.setDefine`.
///
/// Guitar: tap a fret to place that string's note (tap it again to open the string), tap
/// above the nut to toggle open/muted, and step the base fret. Fingers and barres are
/// worked out from the frets. Piano: tap keys to toggle them; the root stays marked.
struct ShapeEditorView: View {
    /// Chord name as written in the source (the define's name).
    let chordName: String
    let instrument: Instrument
    let tuning: Tuning
    /// Starting point: the current resolved shape / voicing, if any.
    var initialGuitar: GuitarShape?
    var initialPiano: PianoVoicing?
    var onSave: (ChordDefinition) -> Void
    var onCancel: () -> Void

    @State private var guitar: GuitarDraft
    @State private var piano: PianoDraft

    init(
        chordName: String,
        instrument: Instrument,
        tuning: Tuning,
        initialGuitar: GuitarShape? = nil,
        initialPiano: PianoVoicing? = nil,
        onSave: @escaping (ChordDefinition) -> Void,
        onCancel: @escaping () -> Void,
    ) {
        self.chordName = chordName
        self.instrument = instrument
        self.tuning = tuning
        self.initialGuitar = initialGuitar
        self.initialPiano = initialPiano
        self.onSave = onSave
        self.onCancel = onCancel
        _guitar = State(initialValue: GuitarDraft(initialGuitar, stringCount: tuning.strings.count))
        _piano = State(initialValue: PianoDraft(initialPiano))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Group {
                switch instrument {
                case .guitar: guitarEditor
                case .piano: pianoEditor
                }
            }
            .frame(maxWidth: .infinity)
            footer
        }
        .padding(20)
        .frame(minWidth: 300)
        .background(Theme.color.ground)
        .accessibilityIdentifier(AccessibilityID.shapeEditor)
    }

    private var header: some View {
        Text(instrument == .guitar ? "Custom shape, \(tuning.name) tuning" : "Custom piano voicing")
            .font(Theme.font.sectionHeading)
            .foregroundStyle(Theme.color.ink)
    }

    // MARK: Guitar

    private var guitarEditor: some View {
        VStack(spacing: 12) {
            GuitarDiagramView(
                name: chordName,
                shape: guitar.shape(stringCount: tuning.strings.count),
                tuning: tuning,
                size: .stage,
                minimumFrets: GuitarDraft.visibleFrets,
                showsFingers: true,
            ) { string, fret in
                guitar.tap(string: string, fret: fret, stringCount: tuning.strings.count)
            }
            HStack(spacing: 8) {
                Text(guitar
                    .baseFret == 1 ? "Starts at the nut" : "Starts at fret \(guitar.baseFret)")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.ink)
                    .monospacedDigit()
                    .frame(minWidth: 130, alignment: .leading)
                Button {
                    guitar.baseFret -= 1
                } label: {
                    Image(systemName: "minus").frame(width: 12, height: 14)
                }
                .disabled(guitar.baseFret <= 1)
                .accessibilityLabel("Lower base fret")
                Button {
                    guitar.baseFret += 1
                } label: {
                    Image(systemName: "plus").frame(width: 12, height: 14)
                }
                .disabled(guitar.baseFret >= GuitarDraft.maxBaseFret)
                .accessibilityLabel("Raise base fret")
            }
            .buttonStyle(.segueSecondary)
            .controlSize(.small)
            if !guitar.isFingerable(stringCount: tuning.strings.count) {
                Text("Needs more than four fingers; saved without fingering.")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
            }
        }
    }

    // MARK: Piano

    private var pianoEditor: some View {
        VStack(spacing: 8) {
            PianoDiagramView(name: chordName, voicing: piano.voicing, size: .stage) { key in
                piano.toggle(key)
            }
            Text("Tap keys to add or remove them.")
                .font(Theme.font.label)
                .foregroundStyle(Theme.color.muted)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Reset", action: reset)
                .buttonStyle(.segueSecondary)
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.segueSecondary)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                if let definition {
                    onSave(definition)
                }
            }
            .buttonStyle(.seguePrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(definition == nil)
            .accessibilityIdentifier(AccessibilityID.shapeEditorSave)
        }
        .controlSize(.regular)
    }

    /// The `{define}` for the current draft; `nil` while nothing sounds.
    private var definition: ChordDefinition? {
        switch instrument {
        case .guitar:
            guitar.definition(name: chordName, stringCount: tuning.strings.count)
        case .piano:
            piano.definition(name: chordName)
        }
    }

    private func reset() {
        guitar = GuitarDraft(initialGuitar, stringCount: tuning.strings.count)
        piano = PianoDraft(initialPiano)
    }
}

/// The guitar shape being edited: frets relative to `baseFret`, as in a `{define}`.
struct GuitarDraft: Equatable {
    /// Rows shown while editing (one more than a chart diagram, for room).
    static let visibleFrets = 5
    /// Highest base fret the editor offers.
    static let maxBaseFret = 20

    var frets: [Int?] = []
    var baseFret = 1

    init() {}

    init(_ shape: GuitarShape?, stringCount: Int) {
        let source = shape?.frets ?? []
        frets = (0 ..< stringCount).map { string in
            string < source.count ? source[string] : 0
        }
        baseFret = shape?.baseFret ?? 1
    }

    /// Tapping a fret places the note there, or opens the string when it already sits
    /// there; tapping the marker row (`fret` 0) toggles open and muted.
    mutating func tap(string: Int, fret: Int, stringCount: Int) {
        normalise(stringCount: stringCount)
        guard frets.indices.contains(string) else { return }
        if fret == 0 {
            frets[string] = frets[string] == nil ? 0 : nil
        } else {
            frets[string] = frets[string] == fret ? 0 : fret
        }
    }

    func shape(stringCount: Int) -> GuitarShape {
        var copy = self
        copy.normalise(stringCount: stringCount)
        let absolute = copy.frets.map { fret in fret.map { $0 == 0 ? 0 : baseFret - 1 + $0 } }
        let assignment = GuitarFingering.assign(absoluteFrets: absolute)
        return GuitarShape(
            frets: copy.frets,
            fingers: assignment?.fingers ?? [],
            baseFret: baseFret,
            barres: assignment?.barre.map { barre in
                [Barre(
                    fret: barre.fret - baseFret + 1,
                    strings: barre.strings,
                    finger: barre.finger,
                )]
            } ?? [],
        )
    }

    func isFingerable(stringCount: Int) -> Bool {
        let shape = shape(stringCount: stringCount)
        return GuitarFingering.assign(absoluteFrets: shape.absoluteFrets) != nil
    }

    func definition(name: String, stringCount: Int) -> ChordDefinition? {
        let shape = shape(stringCount: stringCount)
        guard shape.frets.contains(where: { $0 != nil }) else { return nil }
        return ChordDefinition(name: name, shape: .guitar(shape))
    }

    private mutating func normalise(stringCount: Int) {
        if frets.count < stringCount {
            frets += [Int?](repeating: 0, count: stringCount - frets.count)
        } else if frets.count > stringCount {
            frets.removeLast(frets.count - stringCount)
        }
    }
}

/// The piano voicing being edited, as pitch classes over a fixed root.
struct PianoDraft: Equatable {
    var root = PitchClass(0)
    var keys: Set<PitchClass> = []
    var bass: Int?

    init() {}

    init(_ voicing: PianoVoicing?) {
        root = voicing?.root ?? PitchClass(0)
        keys = Set(voicing?.foldedPitchClasses ?? [])
        bass = voicing?.bass
    }

    mutating func toggle(_ key: PitchClass) {
        if keys.contains(key) {
            keys.remove(key)
        } else {
            keys.insert(key)
        }
    }

    /// Semitones above the root, ascending: the `{define ... keys}` values.
    var offsets: [Int] {
        keys.map { root.semitones(to: $0) }.sorted()
    }

    /// The draft as a displayable voicing (root octave from C4).
    var voicing: PianoVoicing {
        PianoVoicing(notes: offsets.map { 60 + root.rawValue + $0 }, bass: bass, root: root)
    }

    func definition(name: String) -> ChordDefinition? {
        guard !keys.isEmpty else { return nil }
        return ChordDefinition(name: name, shape: .piano(keys: offsets))
    }
}
