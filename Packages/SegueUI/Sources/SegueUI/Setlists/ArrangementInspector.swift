#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// The selected pass (P8-3 section 6.3): its name, pass number and first line, the mode
    /// picker (F / C / 1 / S), Duplicate and Remove.
    struct ArrangementInspector: View {
        let chip: ArrangementDraft.Chip?
        let isReadOnly: Bool
        let canAppend: Bool
        let perform: (ArrangementDraft.Edit) -> Void

        struct ModeItem {
            var mode: PassMode
            var title: String
            var key: String
            var id: String
        }

        static let modes = [
            ModeItem(mode: .full, title: uiString("Full"), key: "F", id: "full"),
            ModeItem(mode: .chordsOnly, title: uiString("Chords only"), key: "C", id: "chords"),
            ModeItem(mode: .firstLine, title: uiString("First line"), key: "1", id: "first"),
            ModeItem(mode: .skip, title: uiString("Skip"), key: "S", id: "skip"),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                titleRow
                // One row where the pane is wide enough; else the buttons under the picker.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        modePicker
                        Spacer(minLength: 0)
                        passButtons
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        modePicker
                        passButtons
                    }
                }
                .disabled(isReadOnly || chip == nil)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.color.line, lineWidth: 1)
            }
        }

        private var passButtons: some View {
            HStack(spacing: 10) {
                smallButton("Duplicate", key: "⌘D", id: AccessibilityID.arrangementDuplicate) {
                    if let chip {
                        perform(.duplicate(chip.id))
                    }
                }
                .disabled(!canAppend)
                smallButton("Remove", key: "⌫", id: AccessibilityID.arrangementRemove) {
                    if let chip {
                        perform(.remove(chip.id))
                    }
                }
            }
            .fixedSize()
        }

        private var titleRow: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(chip?.title ?? uiString("No pass selected"))
                    .font(SchibstedGrotesk.bold.font(size: 15))
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize()
                Text(detail)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }

        /// "pass 2 of 3 · Harbour lights, call me back".
        private var detail: String {
            guard let chip else { return "" }
            var parts: [String] = []
            if let number = chip.number {
                parts.append("pass \(number)")
            }
            if let line = chip.unit.firstLine, !line.isEmpty {
                parts.append(line)
            }
            return parts.joined(separator: " · ")
        }

        private var modePicker: some View {
            HStack(spacing: 0) {
                ForEach(Array(Self.modes.enumerated()), id: \.offset) { offset, item in
                    if offset > 0 {
                        Rectangle().fill(Theme.color.controlBorder).frame(width: 1)
                    }
                    let isOn = chip?.mode == item.mode
                    Button {
                        if let chip {
                            perform(.setMode(chip.id, item.mode))
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(item.title)
                                .font(SchibstedGrotesk.semiBold.font(size: 13))
                            Text(item.key)
                                .font(SchibstedGrotesk.medium.font(size: 11))
                                .opacity(0.6)
                        }
                        .foregroundStyle(isOn ? Theme.color.ground : Theme.color.muted)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(isOn ? Theme.color.ink : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.arrangementMode(item.id))
                }
            }
            .fixedSize()
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
            }
            .accessibilityRepresentation {
                Picker(pickerLabel, selection: Binding(
                    get: { chip?.mode ?? .full },
                    set: { mode in
                        if let chip {
                            perform(.setMode(chip.id, mode))
                        }
                    },
                )) {
                    ForEach(Self.modes, id: \.id) { item in
                        Text(item.title).tag(item.mode)
                    }
                }
            }
        }

        private var pickerLabel: String {
            guard let chip else { return "Show mode" }
            return "Show mode for \(chip.title)" + (chip.number.map { ", pass \($0)" } ?? "")
        }

        private func smallButton(
            _ title: String,
            key: String,
            id: String,
            action: @escaping () -> Void,
        ) -> some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Text(title)
                    Text(key).foregroundStyle(Theme.color.muted)
                }
                .font(SchibstedGrotesk.semiBold.font(size: 12))
                .foregroundStyle(Theme.color.ink)
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.color.controlBorder, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
        }
    }

    /// The optional typed roadmap (P8-3 section 6.5): each valid parse previews in the lane
    /// and on the stage; Return or leaving the field commits one undo step; Esc reverts. An
    /// invalid roadmap saves nothing and says why.
    struct ArrangementRoadmapField: View {
        let draft: ArrangementDraft
        let isReadOnly: Bool
        @Binding var text: String
        let error: String?
        @Binding var isFocused: Bool
        let onEdit: (String) -> Void
        let onCommit: () -> Void
        let onRevert: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("ROADMAP (OPTIONAL)", bundle: #bundle)
                    .font(SchibstedGrotesk.bold.font(size: 11))
                    .tracking(0.08 * 11)
                    .foregroundStyle(Theme.color.muted)
                // An AppKit field with its own field editor: spell-check, autocorrect and
                // completion stay off (romanized Hindi labels, section 6.5).
                ComposerTextField(
                    text: text,
                    font: .monospacedSystemFont(ofSize: 15, weight: .semibold),
                    identifier: AccessibilityID.arrangementRoadmap,
                    placeholder: uiString("Roadmap"),
                    accessibilityHint: helpText,
                    focusRequest: 0,
                    selectAllRequest: 0,
                    accessibilityLabel: "Roadmap",
                    accessibilityValue: text,
                    onChange: { new in
                        text = new
                        onEdit(new)
                    },
                    onFocusChange: { isFocused = $0 },
                    onCommand: command,
                )
                .frame(height: 18)
                .padding(.vertical, 9)
                .padding(.horizontal, 11)
                .background(Theme.color.ground, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
                .disabled(isReadOnly)
                help
                Text(error ?? " ")
                    .font(SchibstedGrotesk.semiBold.font(size: 12))
                    .foregroundStyle(Theme.color.cueText)
                    .frame(height: 15, alignment: .leading)
                    .accessibilityHidden(error == nil)
                    .accessibilityIdentifier(AccessibilityID.arrangementRoadmapError)
            }
        }

        private var borderColor: Color {
            if error != nil {
                return Theme.color.cue
            }
            return isFocused ? Theme.color.muted : Theme.color.controlBorder
        }

        /// Return commits and keeps the sheet open; Esc reverts the text first.
        private func command(_ command: ComposerCommand) -> Bool {
            switch command {
            case .accept:
                onCommit()
                return true
            case .escape:
                onRevert()
                return true
            case .backtab, .next, .previous, .tab:
                return false
            }
        }

        private var helpText: String {
            ":ch chords only, :1 first line, -V2 skip, x2 twice, parts \(draft.partList)"
        }

        /// "`:ch` chords only · `:1` first line · `-V2` skip · `x2` twice · parts `I V1 C`".
        private var help: some View {
            let code = { (text: String) in
                Text(text)
                    .font(.system(size: 12, weight: .semibold).monospaced())
                    .foregroundStyle(Theme.color.ink)
            }
            let plain = { (text: String) in
                Text(text).foregroundStyle(Theme.color.muted)
            }
            let chordsOnly = plain(uiString(" chords only · "))
            let firstLine = plain(uiString(" first line · "))
            let skip = plain(uiString(" skip · "))
            let twice = plain(uiString(" twice · parts "))
            return Text("""
            \(code(":ch"))\(chordsOnly)\(code(":1"))\(firstLine)\
            \(code("-V2"))\(skip)\(code("x2"))\(twice)\
            \(code(draft.partList))
            """)
            .font(SchibstedGrotesk.medium.font(size: 12))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
        }
    }
#endif
