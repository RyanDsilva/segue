import Editing
import Foundation
import Library
import Services
import SwiftUI

/// Bass fills from the library's song pane (P8-7d, sections 12.1, 12.7): the preview's span
/// selection, the fill sheet, and parts writes to the sidecar only (no undo here, as for
/// walk-up picks), serialized with the other bass writes.
extension LibraryViewModel {
    /// The song `id` as the preview renders it, for the fill editor.
    func fillSong(_ id: SongID) -> FillSong? {
        guard let record = song(id: id) else { return nil }
        let model = SongSummary.renderModel(
            record,
            userShapes: userShapes,
            bass: instrument?.bassView,
        )
        return FillSong.make(
            title: SongSummary.title(record),
            model: model,
            document: record.document,
            prefs: record.sidecar.bass,
            parts: record.sidecar.parts,
            profile: instrument?.profile,
            canEdit: !record.isReadOnly,
            readOnlyHelp: record.isReadOnly ? "This song was saved by a newer Segue" : nil,
        )
    }

    /// The span selection follows song `record` as rendered in `render`.
    func refreshSpanSelection(_ record: SongRecord, render: RenderModel) {
        if spanSong != record.id {
            spanSelection.clear()
            spanSong = record.id
        }
        let units = SongSections.units(of: record.document)
        let timeline = SongTimeline.build(
            document: record.document,
            sections: render.sections,
            units: units,
            timing: record.sidecar.bass.timing,
            order: nil,
        )
        let parts = record.sidecar.parts.isEmpty ? ResolvedParts.empty : PartAnchors.resolve(
            record.sidecar.parts,
            timeline: timeline,
            units: units,
            sections: render.sections,
        )
        spanSelection.update(timeline: timeline, sections: render.sections, parts: parts)
    }

    /// What the song pane's chord units do with a span.
    func chordSpanActions(_ record: SongRecord, render: RenderModel) -> ChordSpanActions {
        let id = record.id
        return ChordSpanActions(
            selection: spanSelection,
            refresh: { [weak self] in
                guard let self, let current = song(id: id) else { return }
                refreshSpanSelection(current, render: render)
            },
            isEnabled: sound?.isAvailable ?? true,
            disabledHelp: record.isReadOnly ? "This song was saved by a newer Segue" : nil,
            open: { [weak self] span in self?.openFillEditor(songID: id, span: span) },
        )
    }

    private func fillHost(_ id: SongID) -> FillHost {
        FillHost(
            context: .library,
            song: { [weak self] in self?.fillSong(id) },
            writeParts: { [weak self] parts, _ in self?.writeParts(songID: id, parts) },
            writeTiming: { [weak self] _, change in
                self?.writeBassPrefs(songID: id) { change(&$0.timing) }
            },
            sound: sound,
            services: services,
            settings: instrument?.fillEditor ?? FillEditorSettings(defaults: .standard),
            showNote: { [weak self] note in self?.fillNote = note },
        )
    }

    private static func draftKey(_ id: SongID, _ span: ClosedRange<Int>) -> String {
        "\(id)|\(span.lowerBound)|\(span.upperBound)"
    }

    /// Opens the fill editor on `span` of song `id` (nothing opens during a gig).
    func openFillEditor(songID id: SongID, span: ClosedRange<Int>) {
        guard sound?.isAvailable ?? true, let song = fillSong(id) else { return }
        if let kept = fillDrafts.removeValue(forKey: Self.draftKey(id, span)) {
            kept.reopen()
            kept.update(song)
            fillEditor = kept
            return
        }
        let positions = song.timeline.chords.indices.contains(span.upperBound)
            ? song.timeline.chords[span].map(\.position) : []
        let editing = song.resolved.applied.first { $0.positions == positions }?.part
        guard let model = FillEditorModel(
            host: fillHost(id),
            song: song,
            span: span,
            editing: editing,
        ) else { return }
        fillEditor = model
        services.record(.featureUsed(.fillEditor, .library))
    }

    /// The fill editor on saved fill `part` of song `id` (the Walk-ups list).
    func openFillEditor(songID id: SongID, part: PartID) -> FillEditorModel? {
        guard let song = fillSong(id), let span = song.span(of: part) else { return nil }
        let model = FillEditorModel(
            host: fillHost(id),
            song: song,
            span: span,
            editing: song.parts.first { $0.id == part },
        )
        if model != nil {
            services.record(.featureUsed(.fillEditor, .library))
        }
        listFillEditor = model
        return model
    }

    /// The sheet closed; a gig keeps its drafts for the next open of the span.
    func fillEditorClosed(_ model: FillEditorModel, forGig: Bool) {
        if forGig, let id = spanSong {
            fillDrafts[Self.draftKey(id, model.span)] = model
        } else if !forGig {
            spanSelection.clear()
        }
        if fillEditor === model {
            fillEditor = nil
        }
    }

    /// Song > Create Bass Fill... in the library: the pane's span, else its lane's.
    var canCreateFill: Bool {
        guard sound?.isAvailable ?? true, let id = spanSong,
              song(id: id)?.isReadOnly == false
        else { return false }
        if spanSelection.span != nil {
            return spanSelection.problem == nil
        }
        return playAlong?.fillSpan != nil && playAlong?.fillSpanProblem == nil
    }

    func createFillFromMenu() {
        guard let id = spanSong else { return }
        if let span = spanSelection.span, spanSelection.problem == nil {
            openFillEditor(songID: id, span: span)
        } else if let span = playAlong?.fillSpan {
            openFillEditor(songID: id, span: span)
        }
    }

    /// Song `id` changed on disk or in the sidecar: an open fill sheet on it follows.
    func fillSongChanged(_ id: SongID) {
        guard let song = fillSong(id) else { return }
        for sheet in [fillEditor, listFillEditor].compactMap(\.self) where !sheet.isClosed {
            sheet.update(song)
        }
    }

    /// Writes song `id`'s parts to its sidecar, in order with the other bass writes.
    func writeParts(songID id: SongID, _ parts: [Part]) {
        guard let record = song(id: id), !record.isReadOnly else { return }
        let previous = walkUpWrite
        walkUpWrite = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, let current = song(id: id), current.sidecar.parts != parts else {
                return
            }
            do {
                let saved = try await store.updateParts(id: id, parts)
                await applySaved(saved)
            } catch {
                errorMessage = UserMessage.describe(error)
            }
        }
    }

    /// Renames or deletes saved fills from the Walk-ups list.
    func renameFill(songID id: SongID, _ part: PartID, to name: String) {
        guard var parts = song(id: id)?.sidecar.parts,
              let index = parts.firstIndex(where: { $0.id == part })
        else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        parts[index].name = trimmed.isEmpty ? nil : trimmed
        writeParts(songID: id, parts)
    }

    func deleteFills(songID id: SongID, _ ids: [PartID]) {
        guard let parts = song(id: id)?.sidecar.parts else { return }
        writeParts(songID: id, parts.filter { !ids.contains($0.id) })
    }
}

/// The song pane's fills (P8-7 12.1): the span selection follows the song as shown, an open
/// sheet follows its timing and parts, and the sheet itself.
struct LibraryFills: ViewModifier {
    let model: LibraryViewModel
    let record: SongRecord
    let render: RenderModel

    func body(content: Content) -> some View {
        content
            .onChange(of: render, initial: true) {
                model.refreshSpanSelection(record, render: render)
            }
            .onChange(of: record.sidecar.bass) { follow() }
            .onChange(of: record.sidecar.parts) { follow() }
            .fillEditorSheet(
                model.fillEditor,
                set: { model.fillEditor = $0 },
                closed: { sheet, forGig in model.fillEditorClosed(sheet, forGig: forGig) },
                note: Binding(get: { model.fillNote }, set: { model.fillNote = $0 }),
            )
    }

    private func follow() {
        model.refreshSpanSelection(record, render: render)
        model.fillSongChanged(record.id)
    }
}
