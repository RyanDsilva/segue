#if os(macOS)
    import Editing
    import SwiftUI

    /// Visual mode's chord palette (mockup E2 b, "Chords in song"): the song's chords in the
    /// display key. Clicking one picks it up; each click on a chord slot then drops it, until
    /// it is clicked again or Esc. "Add chord" picks up a chord typed in a popover.
    struct ChordPaletteBar: View {
        @Bindable var model: SongEditorViewModel
        @State private var isAdding = false

        var body: some View {
            HStack(spacing: 8) {
                Text("Chords in song", bundle: #bundle)
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.trailing, 6)
                    .fixedSize()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.paletteChords, id: \.self) { chord in
                            PaletteChip(title: chord, isArmed: model.armedChord == chord) {
                                model.armedChord = model.armedChord == chord ? nil : chord
                            }
                        }
                        addChord
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.color.surfaceAlt.opacity(0.5))
            .overlay(alignment: .bottom) { Hairline() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.editorPalette)
        }

        private var addChord: some View {
            Button {
                isAdding = true
            } label: {
                Text("Add chord", bundle: #bundle)
                    .font(SchibstedGrotesk.semiBold.font(size: 14))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                Theme.color.lineStrong,
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2]),
                            )
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.editorAddChord)
            .help(uiString("Pick up a new chord, then click above a syllable to drop it"))
            .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                ChordPopoverView(
                    title: uiString("Pick up a chord"),
                    initial: "",
                    suggestions: { model.displayChordSuggestions(prefix: $0) },
                    onCommit: { chord in
                        isAdding = false
                        model.armedChord = chord
                    },
                    onDelete: nil,
                    onCancel: { isAdding = false },
                )
            }
        }
    }

    /// A palette chip: mockup 5 x 12 padding, radius 6, `cueText` 15 / 700; picked up = ink.
    private struct PaletteChip: View {
        let title: String
        let isArmed: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(SchibstedGrotesk.bold.font(size: 15))
                    .foregroundStyle(isArmed ? Theme.color.ground : Theme.color.cueText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isArmed ? Theme.color.ink : Theme.color.ground),
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isArmed ? Theme.color.ink : Theme.color.controlBorder,
                                lineWidth: 1,
                            )
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.editorPaletteChord)
            .accessibilityAddTraits(isArmed ? .isSelected : [])
            .help(isArmed ?
                uiString("Click a chord slot to drop \(title); click again to put it down") :
                "Pick up \(title)")
        }
    }

    /// The editor status bar (mockup E2 a): problems, caret line and column, file name.
    struct EditorStatusBar: View {
        let model: SongEditorViewModel

        var body: some View {
            HStack(spacing: 20) {
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.color.cueText)
                        .lineLimit(1)
                        .accessibilityIdentifier(AccessibilityID.editorError)
                } else {
                    problems
                }
                // No tabular figures: Schibsted Grotesk's would open a gap before the comma.
                // Never wraps in a narrow window: the file name truncates instead.
                Text("Line \(model.cursor.line), column \(model.cursor.column)", bundle: #bundle)
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.editorCursor)
                Spacer(minLength: 12)
                Text(fileText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityIdentifier(AccessibilityID.editorFileName)
                if UITesting.isActive {
                    // Instrumentation for the E2E suite only: never shown to VoiceOver users.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        // SwiftUI drops the value of an empty element; the label carries it.
                        .accessibilityLabel(uiString("Typing latency \(model.keystrokeSummary)"))
                        .accessibilityIdentifier(AccessibilityID.editorKeystrokeStats)
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(model.inputSettingsReport)
                        .accessibilityIdentifier(AccessibilityID.editorInputSettings)
                }
            }
            .font(SchibstedGrotesk.medium.font(size: 13))
            .foregroundStyle(Theme.color.muted)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Hairline() }
        }

        private var fileText: String {
            let name = model.fileName.map { ($0 as NSString).lastPathComponent } ?? "New song"
            return "ChordPro - \(name)"
        }

        @ViewBuilder private var problems: some View {
            let diagnostics = model.diagnostics
            if diagnostics.isEmpty {
                Text("No problems", bundle: #bundle)
                    .fixedSize()
                    .accessibilityIdentifier(AccessibilityID.editorProblems)
            } else {
                Menu {
                    ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Button(uiString("Line \(diagnostic.line): \(diagnostic.message)")) {
                            model.reveal(diagnostic)
                        }
                        if let fix = diagnostic.fix {
                            Button(uiString("Fix: \(fix.title)")) {
                                model.applyFix(of: diagnostic)
                            }
                            .accessibilityIdentifier(AccessibilityID.editorProblemFix)
                        }
                    }
                } label: {
                    Label(
                        diagnostics.count == 1 ? "1 problem" : "\(diagnostics.count) problems",
                        systemImage: diagnostics.contains { $0.severity == .error }
                            ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(Theme.color.cueText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(diagnostics.first.map { uiString("Line \($0.line): \($0.message)") } ?? "")
                .accessibilityIdentifier(AccessibilityID.editorProblems)
            }
        }
    }

    /// After "Apply to source": the custom shapes to review.
    struct FlaggedDefinesBanner: View {
        let model: SongEditorViewModel

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.color.cue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SchibstedGrotesk.semiBold.font(size: 14))
                        .foregroundStyle(Theme.color.ink)
                    Text(detail)
                        .font(SchibstedGrotesk.medium.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                }
                Spacer(minLength: 12)
                Button(uiString("Dismiss")) { model.dismissFlaggedDefines() }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Theme.color.surfaceAlt)
            .overlay(alignment: .bottom) { Hairline() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.editorFlaggedDefines)
        }

        private var title: String {
            let count = model.flaggedDefines.count
            return count == 1
                ? "1 custom shape needs review"
                : "\(count) custom shapes need review"
        }

        private var detail: String {
            model.flaggedDefines.map { flag in
                let reason = switch flag.reason {
                case .unused: "no longer used"
                case .mismatched: "drawn for the old chord"
                }
                return "\(flag.name) (line \(flag.line)): \(reason)"
            }
            .joined(separator: "  ·  ")
        }
    }
#endif
