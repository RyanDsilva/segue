// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 12.2). The fill
// sheet's header (span, key, feel, tempo, Loop, Click, play), the editor's toolbar (the view
// toggle and the snaps), the articulation buttons and the footer.

import Library
import MusicTheory
import SwiftUI

// MARK: - Header

struct FillSheetHeader: View {
    @Bindable var model: FillEditorModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bass Fill", bundle: #bundle)
                    .font(SchibstedGrotesk.extraBold.font(size: 17))
                    .foregroundStyle(Theme.color.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(model.spanTitle)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let key = model.keyTitle {
                let spoken = key.replacingOccurrences(of: "\u{2192}", with: "to")
                fact(key, label: uiString("Key"), spoken: spoken)
            }
            fact(model.song.genre.title, label: uiString("Feel"), spoken: model.song.genre.title)
            tempoMenu
            Divider().frame(height: 22)
            Toggle(
                uiString("Loop"),
                isOn: Binding(get: { model.looping }, set: { model.setLooping($0) }),
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(SchibstedGrotesk.semiBold.font(size: 12))
            .disabled(!model.canPlay)
            .accessibilityIdentifier(AccessibilityID.fillLoop)
            Toggle(uiString("Click"), isOn: Binding(get: { model.click }, set: {
                model.click = $0
                model.soundSettingsChanged()
            }))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(SchibstedGrotesk.semiBold.font(size: 12))
            .disabled(!model.canPlay)
            .accessibilityIdentifier(AccessibilityID.fillClick)
            playButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .help(model.canPlay ? "" : SoundGate.offHelp)
    }

    private func fact(_ value: String, label: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(SchibstedGrotesk.bold.font(size: 9))
                .tracking(0.7)
                .foregroundStyle(Theme.color.muted)
            Text(value)
                .font(SchibstedGrotesk.bold.font(size: 13))
                .foregroundStyle(Theme.color.ink)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(label) \(spoken)"))
    }

    private var tempoMenu: some View {
        Menu {
            ForEach([1.0, 0.75, 0.5], id: \.self) { factor in
                Button {
                    model.tempoFactor = factor
                    model.soundSettingsChanged()
                } label: {
                    if model.tempoFactor == factor {
                        Label { Text(verbatim: "\(Int(factor * 100))%") } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: "\(Int(factor * 100))%")
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(model
                    .tempoFactor == 1 ? uiString("TEMPO") :
                    uiString("TEMPO \(Int(model.tempoFactor * 100))%"))
                    .font(SchibstedGrotesk.bold.font(size: 9))
                    .tracking(0.7)
                    .foregroundStyle(Theme.color.muted)
                Text(model.tempoTitle)
                    .font(SchibstedGrotesk.bold.font(size: 13))
                    .foregroundStyle(Theme.color.ink)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help(uiString("Hear the fill slower (never saved)"))
        .accessibilityLabel(
            uiString("Tempo \(model.tempoTitle), \(Int(model.tempoFactor * 100)) percent"),
        )
        .accessibilityIdentifier(AccessibilityID.fillTempo)
    }

    private var playButton: some View {
        let sounding = model.isSounding(model.selected)
        return Button {
            model.togglePlay()
        } label: {
            Label(
                sounding ? uiString("Stop") : uiString("Play"),
                systemImage: sounding ? uiString("stop.fill") : uiString("play.fill"),
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.color.ground)
            .frame(width: 30, height: 30)
            .background(Circle().fill(sounding ? Theme.color.cue : Theme.color.ink))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canPlay)
        .help(model.canPlay ? uiString("Play the selected fill (Space)") : SoundGate.offHelp)
    }
}

// MARK: - Toolbar (view toggle and snaps)

struct FillEditorToolbar: View {
    @Bindable var model: FillEditorModel

    var body: some View {
        HStack(spacing: 14) {
            SegmentedGroup {
                ForEach(FillEditorView.allCases, id: \.self) { view in
                    SegmentButton(title: view.title, isOn: model.view == view) {
                        model.view = view
                    }
                    .help(view == .fretboard ? uiString("Fretboard and step grid (\u{2318}1)")
                        : "Piano roll (\u{2318}2)")
                    .accessibilityIdentifier(view == .fretboard ? AccessibilityID.fillViewFretboard
                        : AccessibilityID.fillViewPianoRoll)
                }
            }
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(uiString("View"))
            .accessibilityIdentifier(AccessibilityID.fillView)
            Spacer(minLength: 8)
            snapPicker("Rhythm", selection: $model.rhythm, id: AccessibilityID.fillRhythmSnap) {
                ForEach(FillRhythmSnap.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            snapPicker("Pitch", selection: $model.pitchSnap, id: AccessibilityID.fillPitchSnap) {
                ForEach(FillPitchSnap.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .help(uiString("Where placed notes snap; hold \u{2325} to place any note"))
            if model.view == .fretboard {
                SegmentedGroup {
                    SegmentButton(
                        title: uiString("Frets"),
                        isOn: !model.showsNames,
                        fontSize: 12,
                        horizontalPadding: 8,
                        verticalPadding: 3,
                    ) {
                        model.showsNames = false
                    }
                    SegmentButton(
                        title: uiString("Names"),
                        isOn: model.showsNames,
                        fontSize: 12,
                        horizontalPadding: 8,
                        verticalPadding: 3,
                    ) {
                        model.showsNames = true
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(uiString("Grid labels"))
            }
        }
    }

    private func snapPicker(
        _ title: String,
        selection: Binding<some Hashable>,
        id: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(SchibstedGrotesk.semiBold.font(size: 12))
                .foregroundStyle(Theme.color.muted)
                .fixedSize()
                .accessibilityHidden(true)
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(uiString("\(title) snap"))
                .accessibilityIdentifier(id)
        }
    }
}

// MARK: - Articulations

struct FillArticulationBar: View {
    let model: FillEditorModel

    private struct Key {
        var articulation: Articulation
        var title: String
        var key: KeyEquivalent

        /// "⌥S", "⌥."
        var shortcut: String {
            "\u{2325}" + String(key.character).uppercased()
        }
    }

    private static let keys = [
        Key(articulation: .slide, title: uiString("Slide"), key: "s"),
        Key(articulation: .hammer, title: uiString("Hammer"), key: "h"),
        Key(articulation: .pull, title: uiString("Pull"), key: "p"),
        Key(articulation: .ghost, title: uiString("Ghost"), key: "g"),
        Key(articulation: .staccato, title: uiString("Staccato"), key: "."),
        Key(articulation: .accent, title: uiString("Accent"), key: ">"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.keys, id: \.title) { item in
                let articulation = item.articulation
                let title = item.title
                let isOn = model.has(articulation)
                Button {
                    model.toggle(articulation)
                } label: {
                    Text(title)
                        .font(SchibstedGrotesk.semiBold.font(size: 12))
                        .foregroundStyle(isOn ? Theme.color.ground : Theme.color.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(isOn ? Theme.color.ink : Theme.color.ground),
                        )
                        .overlay(Capsule().strokeBorder(Theme.color.controlBorder, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(item.key, modifiers: .option)
                .help(Text(verbatim: "\(title) (\(item.shortcut))"))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("segue.fill.articulation.\(articulation.rawValue)")
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Footer

struct FillSheetFooter: View {
    @Bindable var model: FillEditorModel
    var focus: FocusState<FillEditorSheet.Region?>.Binding

    var body: some View {
        HStack(spacing: 14) {
            TextField(model.defaultName, text: $model.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused(focus, equals: .name)
                .accessibilityLabel(uiString("Name"))
                .accessibilityIdentifier(AccessibilityID.fillName)
            labelled("Shows on") {
                Picker(uiString("Shows on"), selection: $model.passes) {
                    Text("Every time", bundle: #bundle).tag(PassFilter.all)
                    if model.plays > 1 {
                        Divider()
                        ForEach(1 ... model.plays, id: \.self) { play in
                            Text("Only \(model.playsTitle) #\(play)", bundle: #bundle)
                                .tag(PassFilter.only([play]))
                        }
                        Divider()
                    }
                    Text("Last time", bundle: #bundle).tag(PassFilter.last)
                }
                .accessibilityIdentifier(AccessibilityID.fillShowsOn)
            }
            labelled("Show as") {
                Picker(uiString("Show as"), selection: $model.show) {
                    Text("Names", bundle: #bundle).tag(PartShow.names)
                    Text("Tab", bundle: #bundle).tag(PartShow.tab)
                }
                .accessibilityIdentifier(AccessibilityID.fillShowAs)
            }
            Spacer(minLength: 8)
            if model.editing != nil {
                Button(uiString("Delete Fill")) { model.confirmation = .delete }
                    .buttonStyle(.segueSecondary)
                    .disabled(!model.song.canEdit)
                    .accessibilityIdentifier(AccessibilityID.fillDelete)
            }
            Button(uiString("Cancel")) { model.cancel() }
                .buttonStyle(.segueSecondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(AccessibilityID.fillCancel)
            Button(uiString("Save")) { model.save() }
                .buttonStyle(.seguePrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
                .help(model.saveHelp ?? uiString("Save the fill to this song (Return)"))
                .accessibilityIdentifier(AccessibilityID.fillSave)
        }
        .controlSize(.regular)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func labelled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(SchibstedGrotesk.semiBold.font(size: 12))
                .foregroundStyle(Theme.color.muted)
                .accessibilityHidden(true)
            content()
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel(title)
        }
    }
}
