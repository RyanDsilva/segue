#if os(macOS)
    import Foundation
    import Library
    import Printing
    import Setlists
    import SwiftUI

    // P9-1 spec sections 4 and 6: what File > Export PDF... and Print... target, the snapshot
    // the preview prints, and the sheet itself.

    extension AppModel {
        /// PDF export is possible: a library is open and the stage does not own the keyboard.
        var canExportPDF: Bool {
            session != nil && !isPerforming && !isStartingShow
        }

        /// What File > Export PDF... and Print... act on: two or more selected library songs,
        /// else the focused or shown song, else the shown setlist when it has a song.
        func pdfMenuTarget(focused: SongID?) -> PDFTarget? {
            guard canExportPDF, let session else { return nil }
            if session.section == .library || session.section == nil {
                let selected = session.library.selectedSongs
                if selected.count > 1 {
                    return .selection(selected)
                }
            }
            if let song = menuSong(focused: focused) {
                return .song(song)
            }
            if let setlist = shownSetlist, setlist.songCount > 0 {
                return .setlist(setlist.id)
            }
            return nil
        }

        /// Opens the preview on `target`; `forPrint` focuses its Print button.
        func openPDF(_ target: PDFTarget, forPrint: Bool = false) {
            guard canExportPDF, pdfPreview == nil,
                  let snapshot = pdfSnapshot(target) else { return }
            let services = dependencies.services
            pdfPreview = PDFPreviewModel(
                snapshot: snapshot,
                opensForPrint: forPrint,
                environment: PDFPreviewModel.Environment(
                    record: { services.record($0) },
                    exportPath: polish.launch.exportPath,
                ),
            )
        }

        func closePDF() {
            pdfPreview?.close()
            pdfPreview = nil
        }

        /// The songs and setlist as they are now (spec 6.2: a snapshot).
        func pdfSnapshot(_ target: PDFTarget) -> PDFSnapshot? {
            guard let session else { return nil }
            let library = session.library
            let content: PDFSnapshot.Content
            switch target {
            case let .song(id):
                guard let record = library.song(id: id) else { return nil }
                content = .song(record)
            case let .slot(setlistID, itemID):
                guard let setlist = session.setlists.setlist(setlistID),
                      let entry = setlist.entries.first(where: { $0.itemId == itemID }),
                      let song = entry.songId
                else { return nil }
                let songs = setlist.entries.filter { $0.songId != nil }
                let number = (songs.firstIndex { $0.itemId == itemID } ?? 0) + 1
                content = .slot(PDFSlotSnapshot(
                    setlist: setlist,
                    entry: entry,
                    record: library.song(id: song),
                    number: number,
                    total: songs.count,
                ))
            case let .setlist(id):
                guard let setlist = session.setlists.setlist(id), setlist.songCount > 0 else {
                    return nil
                }
                var records: [SongID: SongRecord] = [:]
                for song in setlist.entries.compactMap(\.songId) {
                    records[song] = library.song(id: song)
                }
                content = .setlist(setlist, records)
            case let .selection(ids):
                let records = ids.compactMap { library.song(id: $0) }
                guard !records.isEmpty else { return nil }
                content = records.count == 1 ? .song(records[0]) : .selection(records)
            }
            return PDFSnapshot(
                content: content,
                profile: instrumentProfile.profile,
                userShapes: library.userShapes,
                defaultChangeover: ChangeoverSetting.stored(),
                date: dependencies.clock.now(),
            )
        }
    }

    /// Opens the PDF preview from a menu or a row (the library's songs, a setlist's slots).
    struct ExportPDFAction {
        var isEnabled: Bool
        var open: @MainActor (PDFTarget, _ forPrint: Bool) -> Void
    }

    extension EnvironmentValues {
        @Entry var exportPDF: ExportPDFAction?
        /// The setlist a builder shows, for its slot rows' Export Slot as PDF...
        @Entry var pdfSetlist: SetlistID?
    }

    /// A song row's Export PDF..., or a multi-selection's Export N Songs as PDF..., which
    /// prints a songbook in list order (spec 5.13, R178).
    struct SongPDFExportItems: View {
        let songID: SongID
        let selection: [SongID]
        @Environment(\.exportPDF) private var exportPDF

        var body: some View {
            if let exportPDF {
                if selection.count > 1 {
                    Button("Export \(selection.count) Songs as PDF\u{2026}") {
                        exportPDF.open(.selection(selection), false)
                    }
                    .disabled(!exportPDF.isEnabled)
                    .accessibilityIdentifier(AccessibilityID.pdfExportSelection)
                } else {
                    Button("Export PDF\u{2026}") { exportPDF.open(.song(songID), false) }
                        .disabled(!exportPDF.isEnabled)
                        .accessibilityIdentifier(AccessibilityID.pdfExportSong)
                }
            }
        }
    }

    public extension View {
        /// The PDF preview sheet over the main window, sized to it.
        func pdfPresentations(_ app: AppModel) -> some View {
            modifier(PDFPresentations(app: app))
        }
    }

    private struct PDFPresentations: ViewModifier {
        let app: AppModel
        @State private var windowSize: CGSize?

        func body(content: Content) -> some View {
            content
                .windowContentSize($windowSize)
                .sheet(item: Binding(
                    get: { app.pdfPreview },
                    set: { model in
                        if model == nil {
                            app.closePDF()
                        }
                    },
                )) { model in
                    PDFPreviewSheet(model: model, windowSize: windowSize) { app.closePDF() }
                        // The root view's guide links sit inside this modifier, so the
                        // sheet gets its own for the Help button.
                        .guideLinks(app.dependencies.workspace)
                }
        }
    }
#endif
