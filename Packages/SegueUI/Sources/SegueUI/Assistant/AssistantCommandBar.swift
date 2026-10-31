#if os(macOS)
    import Library
    import SetAssistant
    import Setlists
    import SwiftUI

    /// The set assistant's command bar above the set in Arrange (R114, design A): one request
    /// line with Build and Rebuild, the chips under it (lexicon chips at once; the local
    /// model's suggestions dashed, naming nothing until clicked), and a status line with the
    /// last build's fit and R107's "N songs left out: no length" button.
    struct AssistantCommandBar: View {
        let setlist: Setlist
        let model: SetAssistantModel
        let library: LibraryViewModel
        @AppStorage(ChangeoverSetting.defaultsKey) private var defaultChangeover = 0
        @FocusState private var fieldFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    field
                    Button("Build") { build(rebuild: false) }
                        .buttonStyle(.seguePrimary)
                        .disabled(!model.canBuild || isReadOnly)
                        .help("Fill this setlist from the request (locked songs and breaks stay)")
                        .accessibilityIdentifier(AccessibilityID.assistantBuild)
                    Button("Rebuild") { build(rebuild: true) }
                        .buttonStyle(.segueSecondary)
                        .disabled(!model.canBuild || isReadOnly || setlist.songCount == 0)
                        .help("Pack the unlocked slots again with a different pick")
                        .accessibilityIdentifier(AccessibilityID.assistantRebuild)
                    GuideHelpButton(.setAssistant)
                }
                .controlSize(.large)
                if !model.chips.isEmpty || model.isSuggesting {
                    chipRow
                }
                if let result = model.result, result.setlist == setlist.id {
                    AssistantStatusLine(setlist: setlist, result: result, library: library)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.assistantBar)
        }

        private var isReadOnly: Bool {
            setlist.readOnly != nil
        }

        private var field: some View {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                TextField(
                    "Describe a set: 45 min, songs I know well, upbeat start, no covers",
                    text: Binding(get: { model.text }, set: { model.text = $0 }),
                )
                .textFieldStyle(.plain)
                .font(SchibstedGrotesk.medium.font(size: 15))
                .foregroundStyle(Theme.color.ink)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .onSubmit { build(rebuild: false) }
                .accessibilityLabel("Set request")
                .accessibilityIdentifier(AccessibilityID.assistantField)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.color.ground),
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        fieldFocused ? Color.accentColor : Theme.color.controlBorder,
                        lineWidth: fieldFocused ? 2 : 1,
                    )
            }
            .disabled(isReadOnly)
        }

        private var chipRow: some View {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(model.chips) { chip in
                    RequestChipView(
                        chip: chip,
                        title: chip.kind.title(filterName: model.filterName),
                        onAccept: { model.accept(chip) },
                        onRemove: { model.remove(chip) },
                    )
                }
                if model.isSuggesting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Local model…")
                            .font(SchibstedGrotesk.semiBold.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Looking for suggestions")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.assistantChips)
        }

        private func build(rebuild: Bool) {
            guard model.canBuild, !isReadOnly else { return }
            let id = setlist.id
            let changeover = defaultChangeover
            Task {
                await model.build(into: id, rebuild: rebuild, defaultChangeover: changeover)
            }
            Task { await model.suggestNow() }
        }
    }

    /// One chip: stated chips are filled with an ✕ to remove; a suggestion is dashed with
    /// a + and applies only when clicked.
    struct RequestChipView: View {
        let chip: RequestChip
        let title: String
        let onAccept: () -> Void
        let onRemove: () -> Void

        var body: some View {
            if chip.origin == .suggested {
                Button(action: onAccept) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.accentColor)
                        Text(title)
                    }
                    .font(SchibstedGrotesk.semiBold.font(size: 12.5))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .overlay {
                        Capsule().strokeBorder(
                            Theme.color.lineStrong,
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]),
                        )
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Suggested: click to use it")
                .accessibilityLabel("Suggested: \(title)")
                .accessibilityHint("Adds it to the request")
                .accessibilityIdentifier(AccessibilityID.assistantSuggestedChip)
            } else {
                HStack(spacing: 6) {
                    Text(title)
                        .font(SchibstedGrotesk.semiBold.font(size: 12.5))
                        .foregroundStyle(Theme.color.ink)
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.color.muted)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                    .accessibilityLabel("Remove \(title)")
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(height: 26)
                .background(Capsule().fill(Theme.color.ink.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Theme.color.controlBorder, lineWidth: 1))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
                .accessibilityIdentifier(AccessibilityID.assistantChip)
            }
        }
    }

    /// "● 34:28 of 35:00 · 8 songs · 41 matched", R107's left-out button, the locked count.
    struct AssistantStatusLine: View {
        let setlist: Setlist
        let result: SetAssistantModel.Result
        let library: LibraryViewModel
        @AppStorage(ChangeoverSetting.defaultsKey) private var defaultChangeover = 0

        var body: some View {
            let timing = SetlistTiming(
                setlist: setlist,
                library: library,
                defaultChangeover: defaultChangeover,
            )
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(fits(timing) ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(summary(timing))
                        .font(SchibstedGrotesk.semiBold.font(size: 12.5))
                        .foregroundStyle(Theme.color.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.assistantStatus)
                let leftOut = result.leftOutNoTime.filter { !setlist.contains($0) }
                if !leftOut.isEmpty {
                    LeftOutButton(songs: leftOut, library: library)
                }
                let locked = setlist.entries.count(where: \.locked)
                if locked > 0 {
                    Text("\(locked) locked")
                        .font(SchibstedGrotesk.medium.font(size: 12.5))
                        .foregroundStyle(Theme.color.muted)
                }
            }
        }

        private func fits(_ timing: SetlistTiming) -> Bool {
            guard let target = result.target else { return true }
            return timing.unknownCount == 0 && abs(timing.total - target) <= result.tolerance
        }

        private func summary(_ timing: SetlistTiming) -> String {
            var parts: [String] = []
            if let target = result.target {
                parts.append("\(timing.totalText) of \(SetlistTiming.format(target))")
            }
            parts.append(setlist.songCount == 1 ? "1 song" : "\(setlist.songCount) songs")
            parts.append("\(result.matching) matched")
            return parts.joined(separator: " · ")
        }
    }
#endif
