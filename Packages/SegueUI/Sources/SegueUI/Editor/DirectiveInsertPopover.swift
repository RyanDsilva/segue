#if os(macOS)
    import AppKit
    import Editing
    import MusicTheory
    import SwiftUI

    /// "Insert Key Change Here..." and its time and tempo siblings (P8-7 section 6.1): one
    /// value, validated, written as one `{key}`, `{time}` or `{tempo}` line before the point.
    struct DirectiveInsertPopover: View {
        let draft: DirectiveDraft
        /// The written key's sounding key under the capo.
        let sounding: (SongKey) -> SongKey
        /// Inserts; returns the problem when it could not.
        let insert: (String) -> String?
        let close: () -> Void

        @State private var key: SongKey
        @State private var text: String
        @State private var problem: String?
        @FocusState private var fieldFocused: Bool

        init(
            draft: DirectiveDraft,
            sounding: @escaping (SongKey) -> SongKey,
            insert: @escaping (String) -> String?,
            close: @escaping () -> Void,
        ) {
            self.draft = draft
            self.sounding = sounding
            self.insert = insert
            self.close = close
            _key = State(initialValue: draft.key)
            _text = State(initialValue: draft.directive == .time ? draft.time : draft.tempo)
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(SchibstedGrotesk.bold.font(size: 14))
                    .foregroundStyle(Theme.color.ink)
                field
                if let problem {
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(Theme.color.cueText)
                        .accessibilityIdentifier(AccessibilityID.directiveInsertProblem)
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: close)
                        .keyboardShortcut(.cancelAction)
                    Button("Insert", action: commit)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.directiveInsertCommit)
                }
                .controlSize(.small)
            }
            .padding(16)
            .frame(width: 280)
            .onAppear { fieldFocused = true }
            .accessibilityIdentifier(AccessibilityID.directiveInsertPopover)
        }

        private var title: String {
            switch draft.directive {
            case .key: "Key Change"
            case .time: "Time Change"
            case .tempo: "Tempo Change"
            }
        }

        @ViewBuilder private var field: some View {
            switch draft.directive {
            case .key:
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Key", selection: $key) {
                        Section("Major") {
                            ForEach(KeyChoices.keys(.major), id: \.self) { Text($0.name).tag($0) }
                        }
                        Section("Minor") {
                            ForEach(KeyChoices.keys(.minor), id: \.self) { Text($0.name).tag($0) }
                        }
                        if !KeyChoices.keys(draft.key.mode).contains(draft.key) {
                            Text(draft.key.name).tag(draft.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(AccessibilityID.directiveInsertKey)
                    if let capo = draft.capoNote {
                        Text("Written key (\(capo): sounds \(sounding(key).name))")
                            .font(.callout)
                            .foregroundStyle(Theme.color.muted)
                    }
                }
            case .tempo, .time:
                HStack(spacing: 8) {
                    TextField(draft.directive == .time ? "3/4" : "96", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        .onChange(of: text) { problem = nil }
                        .accessibilityLabel(draft.directive == .time ? "Time" : "Tempo")
                        .accessibilityIdentifier(AccessibilityID.directiveInsertValue)
                    Text(draft.directive == .time ? "time signature" : "BPM")
                        .font(.callout)
                        .foregroundStyle(Theme.color.muted)
                }
            }
        }

        private func commit() {
            let value = draft.directive == .key ? key.name : text
            if let problem = insert(value) {
                self.problem = problem
                NSSound.beep()
            } else {
                close()
            }
        }
    }
#endif
