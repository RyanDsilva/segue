#if os(macOS)
    import MusicTheory
    import QuartzCore
    import SwiftUI

    // The song card's per-field editors, shown in each token's popover (direction 2,
    // "Tokens"). Each commits one value and closes; Esc closes without writing.

    /// The key picker: the key heard in the chords on top ("Am  from chords"), a Major /
    /// Minor switch and the twelve keys. Picking writes `{key}`; with a capo it is the
    /// shapes key (R101).
    struct KeyPickerView: View {
        let current: String?
        let detected: SongKey?
        let capo: Int
        let onPick: (SongKey?) -> Void
        @State private var mode: KeyMode

        init(
            current: String?,
            detected: SongKey?,
            capo: Int,
            onPick: @escaping (SongKey?) -> Void,
        ) {
            self.current = current
            self.detected = detected
            self.capo = capo
            self.onPick = onPick
            let start = current.flatMap(SongKey.init(parsing:)) ?? detected
            _mode = State(initialValue: start?.mode ?? .major)
        }

        private var currentKey: SongKey? {
            current.flatMap(SongKey.init(parsing:))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if let detected {
                    suggestion(detected)
                }
                HStack {
                    Text("Key")
                        .font(Theme.font.label)
                        .foregroundStyle(Theme.color.muted)
                    Spacer()
                    Picker("Mode", selection: $mode) {
                        Text("Major").tag(KeyMode.major)
                        Text("Minor").tag(KeyMode.minor)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.songCardKeyMode)
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(50), spacing: 5), count: 6),
                    spacing: 5,
                ) {
                    ForEach(KeyChoices.keys(mode), id: \.name) { key in
                        FilterChip(key.name, isOn: currentKey == key) { onPick(key) }
                            .accessibilityIdentifier(AccessibilityID.songCardKeyOption)
                    }
                }
                footer
            }
            .padding(12)
            .frame(width: 349)
        }

        @ViewBuilder private func suggestion(_ key: SongKey) -> some View {
            let matches = currentKey == key
            Button {
                onPick(key)
            } label: {
                HStack(spacing: 8) {
                    Text(key.name)
                        .font(SchibstedGrotesk.semiBold.font(size: 13))
                        .foregroundStyle(Theme.color.ground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.color.ink, in: RoundedRectangle(cornerRadius: 5))
                    Text(matches ? "matches the chords" : "from chords")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .background(Theme.color.surfaceAlt, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("\(key.name), from chords")
            .accessibilityIdentifier(AccessibilityID.songCardKeySuggestion)
        }

        private var footer: some View {
            HStack(alignment: .firstTextBaseline) {
                if capo > 0 {
                    Text("With a capo, this is the shapes key.")
                        .font(SchibstedGrotesk.medium.font(size: 11))
                        .foregroundStyle(Theme.color.muted)
                }
                Spacer(minLength: 8)
                if current != nil {
                    Button("Clear") { onPick(nil) }
                        .buttonStyle(.link)
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .accessibilityIdentifier(AccessibilityID.songCardClear)
                }
            }
        }
    }

    /// Tempo: a BPM field and Tap (R111). Return commits; Tap fills the field as you tap.
    struct TempoEditorView: View {
        let current: Double?
        let onCommit: (String) -> String?
        @State private var text: String
        @State private var problem: String?
        @State private var taps = TapTempo()
        @FocusState private var focused: Bool

        init(current: Double?, onCommit: @escaping (String) -> String?) {
            self.current = current
            self.onCommit = onCommit
            _text = State(initialValue: current.map(SongCardValues.tempoText) ?? "")
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tempo")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                HStack(spacing: 8) {
                    TextField("Tempo", text: $text, prompt: Text("BPM"))
                        .textFieldStyle(.roundedBorder)
                        .font(SchibstedGrotesk.medium.font(size: 13).monospacedDigit())
                        .frame(width: 64)
                        .focused($focused)
                        .onSubmit(commit)
                        .accessibilityLabel("Tempo in beats per minute")
                        .accessibilityIdentifier(AccessibilityID.songCardTempo)
                    Text("BPM")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                    Button("Tap", action: tap)
                        .buttonStyle(.segueSecondary)
                        .help("Tap along with the song; the tempo fills in")
                        .accessibilityHint("Tap repeatedly in time with the song")
                        .accessibilityIdentifier(AccessibilityID.songCardTap)
                    Button("Set", action: commit)
                        .buttonStyle(.segueSecondary)
                        .accessibilityIdentifier(AccessibilityID.songCardSet)
                }
                if let problem {
                    Text(problem)
                        .font(SchibstedGrotesk.medium.font(size: 11))
                        .foregroundStyle(Theme.color.cueText)
                }
            }
            .padding(12)
            .onAppear { focused = true }
        }

        private func tap() {
            if let bpm = taps.tap(at: CACurrentMediaTime()) {
                text = String(bpm)
                problem = nil
            }
        }

        private func commit() {
            problem = onCommit(text)
        }
    }

    /// Time signature: 4/4, 3/4, 6/8, or Other... (any `n/d`).
    struct TimeEditorView: View {
        let current: String?
        let onCommit: (String) -> String?
        @State private var other: String
        @State private var showsOther: Bool
        @State private var problem: String?

        init(current: String?, onCommit: @escaping (String) -> String?) {
            self.current = current
            self.onCommit = onCommit
            let isOther = current.map { !TimeSignatures.common.contains($0) } ?? false
            _other = State(initialValue: isOther ? current ?? "" : "")
            _showsOther = State(initialValue: isOther)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Time signature")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                HStack(spacing: 6) {
                    ForEach(TimeSignatures.common, id: \.self) { signature in
                        FilterChip(signature, isOn: current == signature) {
                            problem = onCommit(signature)
                        }
                        .accessibilityIdentifier(AccessibilityID.songCardTimeOption)
                    }
                    FilterChip("Other…", isOn: showsOther) { showsOther = true }
                        .accessibilityIdentifier(AccessibilityID.songCardTimeOther)
                }
                if showsOther {
                    TextField("Time signature", text: $other, prompt: Text("7/8"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onSubmit { problem = onCommit(other) }
                        .accessibilityIdentifier(AccessibilityID.songCardTime)
                }
                if let problem {
                    Text(problem)
                        .font(SchibstedGrotesk.medium.font(size: 11))
                        .foregroundStyle(Theme.color.cueText)
                }
                if current != nil {
                    Button("Clear") { problem = onCommit("") }
                        .buttonStyle(.link)
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .accessibilityIdentifier(AccessibilityID.songCardClear)
                }
            }
            .padding(12)
        }
    }

    /// Capo: a stepper 0-11, the same edit as the editor top bar's stepper.
    struct CapoEditorView: View {
        let capo: Int
        let onSet: (Int) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Capo")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                HStack(spacing: 10) {
                    Button { onSet(capo - 1) } label: { Image(systemName: "minus") }
                        .buttonStyle(.segueSecondary)
                        .disabled(capo == 0)
                        .accessibilityLabel("Lower capo")
                    Text(capo == 0 ? "None" : "Fret \(capo)")
                        .font(SchibstedGrotesk.semiBold.font(size: 13).monospacedDigit())
                        .frame(minWidth: 52)
                        .accessibilityIdentifier(AccessibilityID.songCardCapo)
                    Button { onSet(capo + 1) } label: { Image(systemName: "plus") }
                        .buttonStyle(.segueSecondary)
                        .disabled(capo >= 11)
                        .accessibilityLabel("Raise capo")
                }
            }
            .padding(12)
            .accessibilityElement(children: .contain)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onSet(capo + 1)
                case .decrement: onSet(capo - 1)
                @unknown default: break
                }
            }
        }
    }
#endif
