import Editing
import Foundation
import Library
import Services

/// Bass fills in the editor (P8-7d, sections 12.1, 12.7): the span selection follows the
/// preview, the fill sheet opens on a span, and every parts write is one undo step on the
/// editor's undo stack, written to the sidecar only.
extension SongEditorViewModel {
    var spanSelection: ChordSpanSelection {
        fills.selection
    }

    /// The span selection's chart lookup is behind the last render.
    var spanStale: Bool {
        get { fills.stale }
        set { fills.stale = newValue }
    }

    /// The fill editor sheet while it is open.
    var fillEditor: FillEditorModel? {
        get { fills.sheet }
        set { fills.sheet = newValue }
    }

    /// A fill sheet opened from the Walk-ups list (presented by the list).
    var listFillEditor: FillEditorModel? {
        get { fills.listSheet }
        set { fills.listSheet = newValue }
    }

    /// Sheets a gig closed, kept for the next open of the same span (never saved).
    var fillDrafts: [ClosedRange<Int>: FillEditorModel] {
        get { fills.drafts }
        set { fills.drafts = newValue }
    }

    /// A one-time note after saving a fill with the bass-note view off.
    var fillNote: String? {
        get { fills.note }
        set { fills.note = newValue }
    }

    /// Writes the song's parts (sidecar only), handed over by the library.
    var persistParts: ((SongID, [Part]) async throws -> SongRecord)? {
        get { fills.persist }
        set { fills.persist = newValue }
    }

    /// After a render: the span lookup is stale (refreshed now while a span is being
    /// selected), and an open fill sheet follows the song.
    func fillsFollowRender() {
        spanStale = true
        if spanSelection.anchor != nil {
            refreshSpanSelection()
        }
        for sheet in [fillEditor, listFillEditor].compactMap(\.self) where !sheet.isClosed {
            if let song = fillSong {
                sheet.update(song)
            }
        }
    }

    /// Makes the span selection's chart lookup follow the last render.
    func refreshSpanSelection() {
        guard spanStale, let renderModel else { return }
        spanStale = false
        let units = SongSections.units(of: snapshot.document)
        let timeline = SongTimeline.build(
            document: snapshot.document,
            sections: renderModel.sections,
            units: units,
            timing: bassPrefs.timing,
            order: nil,
        )
        let resolved = parts.isEmpty ? ResolvedParts.empty : PartAnchors.resolve(
            parts,
            timeline: timeline,
            units: units,
            sections: renderModel.sections,
        )
        spanSelection.update(timeline: timeline, sections: renderModel.sections, parts: resolved)
    }

    /// The canvas's pills (P8-7 12.1): a plain click or ⌥-click anchors the span.
    func anchorFillSpan(line: BlockPath, offset: Int) {
        refreshSpanSelection()
        guard let index = spanSelection.index(line: line, offset: offset) else { return }
        spanSelection.setAnchor(index)
    }

    /// A shift-click on a pill: the span from the last pill clicked or played.
    func extendFillSpan(line: BlockPath, offset: Int) {
        refreshSpanSelection()
        guard let index = spanSelection.index(line: line, offset: offset) else { return }
        spanSelection.extend(to: index)
    }

    /// Whether the pill at `offset` on `line` is inside the span.
    func isInFillSpan(line: BlockPath, offset: Int) -> Bool {
        guard spanSelection.span != nil,
              let index = spanSelection.index(line: line, offset: offset)
        else { return false }
        return spanSelection.place(of: index) != nil
    }

    /// The song as the fill editor reads it (nil before the first render).
    var fillSong: FillSong? {
        guard let renderModel else { return nil }
        return FillSong.make(
            title: title,
            model: renderModel,
            document: snapshot.document,
            prefs: bassPrefs,
            parts: parts,
            profile: instrument?.profile,
            canEdit: canPickWalkUps,
            readOnlyHelp: canPickWalkUps ? nil : "Save the song first",
        )
    }

    /// What the preview's chord units do with a span.
    var chordSpanActions: ChordSpanActions {
        ChordSpanActions(
            selection: spanSelection,
            refresh: { [weak self] in self?.refreshSpanSelection() },
            isEnabled: sound?.isAvailable ?? true,
            disabledHelp: canPickWalkUps ? nil : "Save the song first",
            open: { [weak self] span in self?.openFillEditor(span: span) },
        )
    }

    /// The fill sheet's owner side.
    private var fillHost: FillHost {
        FillHost(
            context: .editor,
            song: { [weak self] in self?.fillSong },
            writeParts: { [weak self] parts, name in self?.setParts(parts, actionName: name) },
            writeTiming: { [weak self] name, change in self?.changeTiming(name, change) },
            sound: sound,
            services: services,
            settings: instrument?.fillEditor ?? FillEditorSettings(defaults: .standard),
            showNote: { [weak self] note in self?.fillNote = note },
        )
    }

    /// Opens the fill editor on `span` (indices into the written-order timeline): on the
    /// saved fill when the span is exactly one, on a draft a gig closed, else new. Nothing
    /// opens during a gig.
    func openFillEditor(span: ClosedRange<Int>) {
        guard sound?.isAvailable ?? true, let song = fillSong else { return }
        if let kept = fillDrafts.removeValue(forKey: span) {
            kept.reopen()
            kept.update(song)
            fillEditor = kept
            return
        }
        let positions = song.timeline.chords.indices.contains(span.upperBound)
            ? song.timeline.chords[span].map(\.position) : []
        let editing = song.resolved.applied.first { $0.positions == positions }?.part
        guard let model = FillEditorModel(
            host: fillHost,
            song: song,
            span: span,
            editing: editing,
        ) else { return }
        fillEditor = model
        services.record(.featureUsed(.fillEditor, .editor))
    }

    /// Opens the fill editor on saved fill `id` (the Walk-ups list).
    func openFillEditor(part id: PartID) -> FillEditorModel? {
        guard let song = fillSong, let span = song.span(of: id) else { return nil }
        let editing = song.parts.first { $0.id == id }
        let model = FillEditorModel(host: fillHost, song: song, span: span, editing: editing)
        if model != nil {
            services.record(.featureUsed(.fillEditor, .editor))
        }
        listFillEditor = model
        return model
    }

    /// Song > Create Bass Fill... (⌥⌘F): the selected span, when it can take a fill.
    var canCreateFill: Bool {
        guard sound?.isAvailable ?? true, canPickWalkUps else { return false }
        if spanSelection.span != nil {
            return spanSelection.problem == nil
        }
        return playAlongStore?.fillSpan.map { _ in true } ?? false
    }

    func createFillFromMenu() {
        if let span = spanSelection.span, spanSelection.problem == nil {
            openFillEditor(span: span)
        } else if let span = playAlongStore?.fillSpan {
            openFillEditor(span: span)
        }
    }

    /// The sheet closed (Save, Cancel, Delete, or a gig: then its drafts are kept).
    func fillEditorClosed(_ model: FillEditorModel, forGig: Bool) {
        if forGig {
            fillDrafts[model.span] = model
        } else {
            spanSelection.clear()
        }
        if fillEditor === model {
            fillEditor = nil
        }
    }

    /// Replaces the song's parts, registers the inverse on the editor's undo stack, redraws
    /// and writes the sidecar (never the `.cho`).
    func setParts(_ new: [Part], actionName: String) {
        let old = parts
        guard new != old, canPickWalkUps else { return }
        parts = new
        #if os(macOS)
            let manager = sourceEditor.undoManager
            manager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.setParts(old, actionName: actionName) }
            }
            manager.setActionName(actionName)
        #endif
        spanStale = true
        scheduleRender(delay: .zero)
        guard case let .edit(id) = mode, let persistParts else { return }
        let previous = fills.task
        fills.task = Task { @MainActor [weak self] in
            await previous?.value
            do {
                _ = try await persistParts(id, new)
            } catch {
                self?.errorMessage = UserMessage.describe(error)
            }
        }
    }

    /// Renames saved fill `id` (the Walk-ups list), one undo step.
    func renameFill(_ id: PartID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var new = parts
        guard let index = new.firstIndex(where: { $0.id == id }) else { return }
        new[index].name = trimmed.isEmpty ? nil : trimmed
        setParts(new, actionName: "Rename Fill")
    }

    /// Deletes saved fills (the Walk-ups list), one undo step.
    func deleteFills(_ ids: [PartID]) {
        setParts(parts.filter { !ids.contains($0.id) }, actionName: "Delete Fill")
    }
}

/// The editor's fill state (P8-7d), observed so the sheet and its note present.
@MainActor
@Observable
final class EditorFills {
    var sheet: FillEditorModel?
    @ObservationIgnored weak var listSheet: FillEditorModel?
    @ObservationIgnored var drafts: [ClosedRange<Int>: FillEditorModel] = [:]
    var note: String?
    @ObservationIgnored let selection = ChordSpanSelection()
    @ObservationIgnored var stale = true
    @ObservationIgnored var persist: ((SongID, [Part]) async throws -> SongRecord)?
    /// The last parts write; the next one waits for it.
    @ObservationIgnored var task: Task<Void, Never>?
}
