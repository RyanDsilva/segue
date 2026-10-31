// P8-7d (docs/phases/8-workstreams/P8-7-time-model-and-fills.md sections 12.2-12.8). The fill
// sheet (`segue.fill.editor`): header, chord lane, the candidates beside the editor
// (Fretboard | Piano Roll), the mini tab, and the footer. Resizable, default 1040 x 700,
// at least 860 x 600; follows the appearance.

import AppKit
import Diagrams
import Library
import MusicTheory
import SwiftUI

struct FillEditorSheet: View {
    let model: FillEditorModel
    /// Called once when the sheet closes (`forGig`: a gig closed it, its drafts are kept).
    let onClose: (_ forGig: Bool) -> Void
    /// The content size of the window the sheet opens over (nil: not known yet).
    var windowSize: CGSize?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Region?

    enum Region: Hashable {
        case candidates
        case editor
        case name
    }

    var body: some View {
        VStack(spacing: 0) {
            FillSheetHeader(model: model)
            Rule()
            if let lane = model.lane {
                TimelineStrip(model: lane)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottomTrailing) {
                        if model.isEstimated {
                            Label(
                                "Chord lengths are estimated - set them here",
                                systemImage: "info.circle",
                            )
                            .font(SchibstedGrotesk.medium.font(size: 12))
                            .foregroundStyle(Theme.color.muted)
                            .padding(.trailing, 20)
                            .padding(.bottom, 14)
                        }
                    }
                    .background(Theme.color.surfaceAlt.opacity(0.35))
                Rule()
            }
            HStack(spacing: 0) {
                FillCandidatesColumn(model: model, focused: focus == .candidates)
                    .focusable()
                    .focused($focus, equals: .candidates)
                    .focusEffectDisabled()
                    .onKeyPress(phases: .down) { press in candidatesKey(press) }
                Rectangle().fill(Theme.color.line).frame(width: 1)
                editor
            }
            .frame(maxHeight: .infinity)
            Rule()
            miniTab
            Rule()
            FillSheetFooter(model: model, focus: $focus)
        }
        .frame(width: Self.size(in: windowSize).width, height: Self.size(in: windowSize).height)
        .background(Theme.color.ground)
        .background(hiddenShortcuts)
        .onKeyPress(.space, phases: .down) { _ in
            guard focus != .name else { return .ignored }
            model.togglePlay()
            return .handled
        }
        .onChange(of: model.isClosed) { _, closed in
            guard closed else { return }
            onClose(model.closedForGig)
            dismiss()
        }
        .onChange(of: model.host.sound?.gate.gigRunning == true) { _, running in
            if running {
                model.closeForGig()
            }
        }
        .onAppear { focus = .editor }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { model.confirmation != nil },
                set: {
                    if !$0 {
                        model.confirmation = nil
                    }
                },
            ),
            titleVisibility: .visible,
        ) {
            switch model.confirmation {
            case .replace:
                Button("Replace", role: .destructive) { model.confirmReplace() }
            case .delete:
                Button("Delete Fill", role: .destructive) { model.delete() }
            case nil:
                EmptyView()
            }
            Button("Cancel", role: .cancel) { model.confirmation = nil }
        } message: {
            switch model.confirmation {
            case .replace:
                Text("This fill shares a chord change with it. The other fill is removed.")
            case .delete:
                Text("Its walk-ups show again where it played.")
            case nil:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.fillEditor)
    }

    private var confirmationTitle: String {
        switch model.confirmation {
        case let .replace(names):
            names.count == 1 ? "Replace \u{201C}\(names[0])\u{201D}?"
                : "Replace \(names.count) fills?"
        case .delete: "Delete this fill?"
        case nil: ""
        }
    }

    // MARK: Editor

    /// The design's 1040 x 700 where the window has room; in a smaller window, the window
    /// less a margin, down to 760 x 480 (section 12.2's 860 x 600 minimum does not fit the
    /// app's smallest window, 820 x 520).
    static func size(in window: CGSize?) -> CGSize {
        guard let window else { return CGSize(width: 1040, height: 700) }
        return CGSize(
            width: min(1040, max(760, window.width - 48)),
            height: min(700, max(480, window.height - 40)),
        )
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            FillEditorToolbar(model: model)
            Group {
                switch model.view {
                case .fretboard:
                    // Scrolls in a short window rather than clipping the grid.
                    ScrollView(.vertical) {
                        FillFretboardGrid(model: model, focused: focus == .editor)
                    }
                    .scrollIndicators(.automatic)
                case .pianoRoll:
                    FillPianoRoll(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .focusable()
            .focused($focus, equals: .editor)
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in editorKey(press) }
            .overlay(alignment: .topTrailing) {
                if focus == .editor {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.color.cue.opacity(0.35), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            if model.view == .fretboard {
                FillArticulationBar(model: model)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var miniTab: some View {
        let grid = model.grid
        return VStack(alignment: .leading, spacing: 0) {
            MiniTabView(
                notes: model.tabNotes,
                chords: model.tabChords,
                ticks: grid.region,
                pulses: grid.pulses,
                bars: grid.bars.map(\.tick),
                tuning: grid.tuning,
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    /// ⌘Z / ⇧⌘Z on the sheet's own undo stack; ⌘1 / ⌘2 switch the view.
    private var hiddenShortcuts: some View {
        ZStack {
            Button("Undo") { model.draft.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.draft.canUndo || focus == .name)
            Button("Redo") { model.draft.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.draft.canRedo || focus == .name)
            Button("Fretboard") { model.view = .fretboard }
                .keyboardShortcut("1", modifiers: .command)
            Button("Piano Roll") { model.view = .pianoRoll }
                .keyboardShortcut("2", modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Keys

    private func candidatesKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            model.moveSelection(by: -1)
            return .handled
        case .downArrow:
            model.moveSelection(by: 1)
            return .handled
        default:
            guard press.modifiers.isDisjoint(with: [.command, .option, .control]),
                  let letter = press.characters.first, "abcdeABCDE".contains(letter)
            else { return .ignored }
            model.select(letter: letter)
            return .handled
        }
    }

    private func editorKey(_ press: KeyPress) -> KeyPress.Result {
        model.view == .fretboard ? gridKey(press) : rollKey(press)
    }

    private func gridKey(_ press: KeyPress) -> KeyPress.Result {
        let draft = model.draft
        let shift = press.modifiers.contains(.shift)
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return .ignored
        }
        switch press.key {
        case .leftArrow:
            draft.moveCursor(by: -1, extending: shift, rhythm: model.rhythm, on: model.grid)
        case .rightArrow:
            draft.moveCursor(by: 1, extending: shift, rhythm: model.rhythm, on: model.grid)
        case .upArrow:
            draft.moveString(by: 1, on: model.grid)
        case .downArrow:
            draft.moveString(by: -1, on: model.grid)
        case .delete, .deleteForward:
            model.rest(in: .fretboard)
        default:
            return gridCharacter(press.characters)
        }
        return .handled
    }

    /// `+` / `-`, `R` and the fret digits on the grid.
    private func gridCharacter(_ characters: String) -> KeyPress.Result {
        switch characters {
        case "+", "=": model.lengthen(by: 1, in: .fretboard)
        case "_", "-": model.lengthen(by: -1, in: .fretboard)
        case "r", "R": model.rest(in: .fretboard)
        default:
            guard let digit = Int(characters), (0 ... 9).contains(digit) else {
                return .ignored
            }
            model.typeFret(digit, at: ProcessInfo.processInfo.systemUptime)
        }
        return .handled
    }

    private func rollKey(_ press: KeyPress) -> KeyPress.Result {
        let shift = press.modifiers.contains(.shift)
        if press.modifiers.contains(.command) {
            guard press.characters.lowercased() == "a" else { return .ignored }
            model.draft.selectAll()
            return .handled
        }
        guard press.modifiers.isDisjoint(with: [.option, .control]) else { return .ignored }
        switch press.key {
        case .upArrow: model.transposeSelection(by: 1, octave: shift)
        case .downArrow: model.transposeSelection(by: -1, octave: shift)
        case .leftArrow: model.nudgeSelection(by: -1)
        case .rightArrow: model.nudgeSelection(by: 1)
        case .delete, .deleteForward:
            model.rest(in: .pianoRoll)
        default:
            return rollCharacter(press.characters)
        }
        return .handled
    }

    private func rollCharacter(_ characters: String) -> KeyPress.Result {
        switch characters {
        case "+", "=": model.lengthen(by: 1, in: .pianoRoll)
        case "_", "-": model.lengthen(by: -1, in: .pianoRoll)
        default: return .ignored
        }
        return .handled
    }
}

// MARK: - Presenting

extension View {
    /// Presents the fill editor while `model` is set, sized to the window it opens over;
    /// `closed` tells the owner how it closed. `note` is the one-time note after a save with
    /// the bass-note view off.
    func fillEditorSheet(
        _ model: FillEditorModel?,
        set: @escaping @MainActor (FillEditorModel?) -> Void,
        closed: @escaping @MainActor (FillEditorModel, Bool) -> Void,
        note: Binding<String?>,
    ) -> some View {
        modifier(FillEditorPresenter(model: model, set: set, closed: closed, note: note))
    }
}

struct FillEditorPresenter: ViewModifier {
    let model: FillEditorModel?
    let set: @MainActor (FillEditorModel?) -> Void
    let closed: @MainActor (FillEditorModel, Bool) -> Void
    @Binding var note: String?
    @State private var windowSize: CGSize?

    func body(content: Content) -> some View {
        content
            .windowContentSize($windowSize)
            .sheet(item: Binding(get: { model }, set: { set($0) })) { sheet in
                FillEditorSheet(
                    model: sheet,
                    onClose: { forGig in closed(sheet, forGig) },
                    windowSize: windowSize,
                )
            }
            .alert(
                "Fill saved",
                isPresented: Binding(get: { note != nil }, set: {
                    if !$0 {
                        note = nil
                    }
                }),
            ) {
                Button("OK") { note = nil }
            } message: {
                Text(note ?? "")
            }
    }
}
