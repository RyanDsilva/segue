#if os(macOS)
    import AppKit
    import Library
    import Setlists
    import Shows
    import SwiftUI

    /// "Arrange Sections" (P8-3, R149, design B1): the song's parts in a palette, the slot's
    /// passes as a lane of chips with a show mode each, the selected pass's inspector, an
    /// optional typed roadmap, and the live stage preview. Each edit saves at once as one
    /// builder undo step; the `.cho` is never changed. Opened from the slot popover's Sections
    /// row, the slot context menu, Setlist > Arrange Sections… and the pre-show checklist.
    struct ArrangementEditorSheet: View {
        let slot: ArrangingSlot
        let model: SetlistsViewModel
        let library: LibraryViewModel
        /// The content size of the window the sheet opens over (nil: not known yet).
        var windowSize: CGSize?
        @Environment(\.dismiss) private var dismiss
        @Environment(\.arrangementStage) private var stage
        @State private var editor: ArrangementEditor

        init(
            slot: ArrangingSlot,
            model: SetlistsViewModel,
            library: LibraryViewModel,
            windowSize: CGSize? = nil,
        ) {
            self.slot = slot
            self.model = model
            self.library = library
            self.windowSize = windowSize
            _editor = State(initialValue: ArrangementEditor(slot: slot, model: model))
        }

        var body: some View {
            if let setlist = model.setlist(slot.setlist),
               // A medley member edits exactly like a song slot (P9-3 5.5).
               let entry = setlist.songSlot(slot.item)?.asEntry,
               let songID = entry.songId,
               let record = library.song(id: songID)
            {
                ArrangementEditorContent(
                    setlist: setlist,
                    entry: entry,
                    record: record,
                    library: library,
                    units: SongSections.units(of: record.document),
                    editor: editor,
                    isReadOnly: setlist.readOnly != nil || library.isPerforming,
                    stage: stage,
                    size: Self.size(in: windowSize),
                    done: { dismiss() },
                    rehearse: { rehearse(songID) },
                )
            } else {
                VStack(spacing: 14) {
                    Text("This song is no longer in the set or the library.")
                        .foregroundStyle(Theme.color.muted)
                    Button("Done") { dismiss() }
                        .buttonStyle(.seguePrimary)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(32)
            }
        }

        /// "Rehearse this" (R156): waits for the queued saves, closes the sheet and plays this
        /// slot (its key, capo and arrangement) as an unlogged one-song rehearsal; when that
        /// ends the sheet opens again for the same slot.
        private func rehearse(_ song: SongID) {
            guard let stage else { return }
            let editor = editor
            let model = model
            let slot = slot
            Task {
                await editor.settle()
                guard let entry = model.setlist(slot.setlist)?.songSlot(slot.item)?.asEntry
                else { return }
                model.services.record(.featureUsed(.arrangementRehearse, .builder))
                model.arranging = nil
                stage.rehearse(song, StageSlot(entry)) { model.arranging = slot }
            }
        }
    }

    private struct ArrangementEditorContent: View {
        let setlist: Setlist
        let entry: SetlistEntry
        let record: SongRecord
        let library: LibraryViewModel
        let units: [SongSectionUnit]
        let editor: ArrangementEditor
        let isReadOnly: Bool
        let stage: ArrangementStage?
        /// The sheet's size (`ArrangementEditorSheet.size(in:)`).
        let size: CGSize
        let done: () -> Void
        let rehearse: () -> Void

        @State private var dragging: ArrangementDrag?
        @State private var roadmapText = ""
        @State private var roadmapError: String?
        @FocusState private var laneFocused: Bool
        @State private var roadmapFocused = false

        /// The lane as saved (or pending), without a roadmap being typed.
        private var base: ArrangementDraft {
            ArrangementDraft(
                arrangement: editor.arrangement(saved: entry.arrangement),
                units: units,
            )
        }

        /// The lane as shown: a valid roadmap being typed replaces the passes.
        private var draft: ArrangementDraft {
            let base = base
            return editor.roadmapPreview.map(base.with(passes:)) ?? base
        }

        private var selection: Int {
            min(editor.selection, max(draft.chips.count - 1, 0))
        }

        var body: some View {
            let draft = draft
            VStack(spacing: 0) {
                header(draft)
                if draft.isOutOfDate {
                    missingBanner(draft)
                }
                Rule()
                HStack(spacing: 0) {
                    leftPane(draft)
                        .frame(width: ArrangementEditorSheet.paneWidth(sheetWidth: size.width))
                        .background(Theme.color.surfaceAlt.opacity(0.35))
                    Rule(axis: .vertical)
                    ArrangementPreview(
                        record: record,
                        entry: entry,
                        arrangement: previewArrangement(draft),
                        settings: stage?.settings.settings ?? LiveSettings(),
                        bass: stage?.instrument?.bassView,
                        selection: draft.chips.indices.contains(selection) ? selection : nil,
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Rule()
                footer(draft)
            }
            .frame(width: size.width, height: size.height)
            .background(Theme.color.ground)
            .onAppear {
                roadmapText = draft.roadmap
                laneFocused = true
            }
            .onChange(of: draft.roadmap) { _, roadmap in
                if !roadmapFocused {
                    roadmapText = roadmap
                }
            }
            .onChange(of: draft.chips.count) { _, count in editor.clampSelection(count: count) }
            .onChange(of: roadmapFocused) { _, focused in
                if !focused {
                    commitRoadmap()
                }
            }
            .onExitCommand(perform: finish)
        }

        /// What the stage would show now: the lane (the full song's passes for a slot without
        /// an arrangement, so the selection maps to a pass); out of date stays out of date.
        private func previewArrangement(_ draft: ArrangementDraft) -> SlotArrangement? {
            if draft.isOutOfDate, editor.roadmapPreview == nil {
                return editor.arrangement(saved: entry.arrangement)
            }
            return draft.arrangement
        }

        // MARK: Header

        private func header(_ draft: ArrangementDraft) -> some View {
            HStack(spacing: 12) {
                Text("Arrange Sections")
                    .font(SchibstedGrotesk.extraBold.font(size: 17))
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                    // On the title, not the sheet: an identifier on a container would replace
                    // every control's own.
                    .accessibilityIdentifier(AccessibilityID.arrangementSheet)
                Text(subtitle)
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // In a narrow sheet the subtitle gives way, never the buttons.
                    .layoutPriority(-1)
                Spacer(minLength: 8)
                Button(action: rehearse) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Rehearse this")
                        Text("⌥⌘↩").foregroundStyle(Theme.color.muted).fontWeight(.medium)
                    }
                }
                .buttonStyle(.segueSecondary)
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(!canRehearse(draft))
                .help(rehearseHelp(draft))
                .accessibilityIdentifier(AccessibilityID.arrangementRehearse)
                Button("Reset to Full Song") {
                    editor.roadmapPreview = nil
                    editor.reset()
                }
                .buttonStyle(.segueSecondary)
                .disabled(!draft.isCustom || isReadOnly)
                .accessibilityIdentifier(AccessibilityID.arrangementReset)
                Button("Done", action: finish)
                    .buttonStyle(.seguePrimary)
                    .keyboardShortcut(roadmapFocused ? nil : .defaultAction)
                    .accessibilityIdentifier(AccessibilityID.arrangementDone)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
        }

        /// "Harbor Lights · Friday · slot 4" ("slot 4b" for a medley member).
        private var subtitle: String {
            let number = setlist.songSlotLabels.first { $0.slot.itemId == entry.itemId }?.label
                ?? "1"
            return "\(SongSummary.title(record)) · \(setlist.name) · slot \(number)"
        }

        private func canRehearse(_ draft: ArrangementDraft) -> Bool {
            guard let stage else { return false }
            return stage.canRehearse && !draft.isOutOfDate
        }

        private func rehearseHelp(_ draft: ArrangementDraft) -> String {
            if draft.isOutOfDate {
                return "Update the arrangement first"
            }
            return "Rehearse this slot as arranged, in its key and capo (not logged)"
        }

        private func missingBanner(_ draft: ArrangementDraft) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.color.cueText)
                    .accessibilityHidden(true)
                Text(Self.missingText(draft))
                    .font(SchibstedGrotesk.medium.font(size: 13))
                    .foregroundStyle(Theme.color.cueText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Update") { perform(.update) }
                    .buttonStyle(.segueSecondary)
                    .disabled(isReadOnly)
                    .help("Keep the passes that still match the song and drop the rest")
                    .accessibilityIdentifier(AccessibilityID.arrangementUpdate)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.color.cue.opacity(0.08))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.arrangementMissing)
        }

        static func missingText(_ draft: ArrangementDraft) -> String {
            let what = draft.missing.isEmpty
                ? "this arrangement can't be played as saved."
                : "no longer in the song: \(draft.missingNames)."
            return "Out of date: \(what) The stage shows the full song until you update."
        }

        // MARK: Left pane

        private func leftPane(_ draft: ArrangementDraft) -> some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        eyebrow("Song parts - click or drag into the sequence")
                        ArrangementPalette(
                            draft: draft,
                            selection: selection,
                            isReadOnly: isReadOnly,
                            dragging: $dragging,
                            perform: perform,
                        )
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        eyebrow("Sequence")
                        lane(draft)
                    }
                    ArrangementInspector(
                        chip: draft.chips.indices.contains(selection) ? draft
                            .chips[selection] : nil,
                        isReadOnly: isReadOnly,
                        canAppend: draft.chips.count < SlotArrangement.maxPasses,
                        perform: perform,
                    )
                    ArrangementRoadmapField(
                        draft: base,
                        isReadOnly: isReadOnly,
                        text: $roadmapText,
                        error: roadmapError,
                        isFocused: $roadmapFocused,
                        onEdit: editRoadmap,
                        onCommit: commitRoadmap,
                        onRevert: revertRoadmap,
                    )
                    Text("← → select · ⌥← ⌥→ move · F C 1 S mode · ⌫ remove · ⌘D duplicate")
                        .font(SchibstedGrotesk.medium.font(size: 12))
                        .foregroundStyle(Theme.color.muted)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
            }
        }

        private func eyebrow(_ text: String) -> some View {
            Text(text.uppercased())
                .font(SchibstedGrotesk.bold.font(size: 11))
                .tracking(0.08 * 11)
                .foregroundStyle(Theme.color.muted)
        }

        private func lane(_ draft: ArrangementDraft) -> some View {
            ArrangementLane(
                draft: draft,
                selection: selection,
                isReadOnly: isReadOnly,
                dragging: $dragging,
                select: { index in
                    editor.select(index, count: draft.chips.count)
                    laneFocused = true
                },
                perform: perform,
            )
            .focusable()
            .focusEffectDisabled()
            .focused($laneFocused)
            .onKeyPress(phases: .down) { press in keyPress(press) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Sequence, " + ArrangementPreview.spokenCount(draft.chips.count)
                    + (draft.skippedCount > 0 ? ", \(draft.skippedCount) skipped" : ""),
            )
            .accessibilityIdentifier(AccessibilityID.arrangementLane)
        }

        // MARK: Footer

        private func footer(_ draft: ArrangementDraft) -> some View {
            HStack(spacing: 10) {
                GuideHelpButton(.arrangeSections)
                SlotTimeFooter(
                    time: library.times.slot(record, arrangement: draft.arrangement),
                    record: record,
                    library: library,
                    isReadOnly: isReadOnly,
                )
                Spacer(minLength: 8)
                // The note drops before anything else does in a narrow sheet.
                ViewThatFits(in: .horizontal) {
                    Text(draft.footerCounts + " · this gig only, the song is not changed")
                    Text(draft.footerCounts)
                }
                .lineLimit(1)
                .layoutPriority(-1)
            }
            .font(SchibstedGrotesk.medium.font(size: 13))
            .foregroundStyle(Theme.color.muted)
            .padding(.horizontal, 18)
            .frame(height: 52)
        }
    }

    extension ArrangementEditorContent {
        // MARK: Edits

        /// Applies an edit to the newest draft and queues its save; a refused edit beeps.
        private func perform(_ edit: ArrangementDraft.Edit) {
            guard !isReadOnly else { return }
            let draft = draft
            editor.roadmapPreview = nil
            if let refusal = editor.perform(edit, on: draft), refusal != .nothingChanged {
                NSSound.beep()
                if let message = refusal.message {
                    AccessibilityNotification.Announcement(message).post()
                }
            }
        }

        private func finish() {
            commitRoadmap()
            done()
        }

        /// The lane's keys (P8-3 section 6.6); never while typing in a field.
        private func keyPress(_ press: KeyPress) -> KeyPress.Result {
            let count = draft.chips.count
            guard count > 0 else { return .ignored }
            let index = selection
            let modifiers = press.modifiers
            switch press.key {
            case .downArrow, .leftArrow, .rightArrow, .upArrow:
                let forward = press.key == .rightArrow || press.key == .downArrow
                if modifiers.contains(.option) {
                    perform(.move(from: index, to: forward ? index + 2 : index - 1))
                } else if modifiers.contains(.command) {
                    editor.select(forward ? count - 1 : 0, count: count)
                } else if press.key == .leftArrow || press.key == .rightArrow {
                    editor.select(index + (forward ? 1 : -1), count: count)
                } else {
                    return .ignored
                }
            case .home:
                editor.select(0, count: count)
            case .end:
                editor.select(count - 1, count: count)
            case .delete, .deleteForward:
                perform(.remove(index))
            default:
                return modeKey(press, index: index)
            }
            return .handled
        }

        /// F, C, 1, S (ignoring ⌘ and ⌃), ⌘D and ⇧⌘D.
        private func modeKey(_ press: KeyPress, index: Int) -> KeyPress.Result {
            let character = press.characters.lowercased()
            if press.modifiers.contains(.command) {
                guard character == "d" else { return .ignored }
                perform(press.modifiers.contains(.shift)
                    ? .playAgainAtEnd(index)
                    : .duplicate(index))
                return .handled
            }
            guard !press.modifiers.contains(.control) else { return .ignored }
            switch character {
            case "f": perform(.setMode(index, .full))
            case "c": perform(.setMode(index, .chordsOnly))
            case "1": perform(.setMode(index, .firstLine))
            case "s": perform(.toggleSkip(index))
            default: return .ignored
            }
            return .handled
        }

        // MARK: Roadmap

        private func editRoadmap(_ text: String) {
            switch base.parseRoadmap(text) {
            case let .success(passes):
                editor.roadmapPreview = passes
                roadmapError = nil
            case .failure(.empty):
                editor.roadmapPreview = nil
                roadmapError = nil
            case let .failure(error):
                if roadmapError != error.message {
                    AccessibilityNotification.Announcement(error.message).post()
                }
                roadmapError = error.message
            }
        }

        /// Return or leaving the field: one undo step "Edit Roadmap"; an invalid or empty
        /// roadmap saves nothing.
        private func commitRoadmap() {
            guard let passes = editor.roadmapPreview else {
                if roadmapText.trimmingCharacters(in: .whitespaces).isEmpty {
                    revertRoadmap()
                }
                return
            }
            let base = base
            editor.roadmapPreview = nil
            roadmapError = nil
            guard !isReadOnly else { return }
            if let refusal = editor.perform(.replace(passes), on: base),
               refusal != .nothingChanged
            {
                NSSound.beep()
                roadmapError = refusal.message
            }
        }

        /// Esc in the field: back to the saved roadmap.
        private func revertRoadmap() {
            editor.roadmapPreview = nil
            roadmapError = nil
            roadmapText = base.roadmap
        }
    }
#endif
