#if os(macOS)
    import CoreTransferable
    import Foundation
    import Library
    import Services
    import Support
    import SwiftUI
    import UniformTypeIdentifiers

    // P9-5 section 5 (P2): a library row drags out as its `.cho` file, so sending a chart to
    // the bass player is a drag into Messages, and a drag to Finder saves a copy. The drop
    // always gets a fresh copy, never the library's own file: Finder would otherwise move it
    // out of the library on a same-volume drop. Nothing drags out while a show is up.

    /// A song's ChordPro file on its way out of the library.
    struct SongFileDrag: Transferable {
        /// The file name the drop gets (the library file's own name).
        let fileName: String
        /// Reads the song's source through the library's file system (security-scoped).
        let read: @Sendable () throws -> Data
        /// Runs once the copy has been handed to the drop (row 8 `songDragOut`).
        let onExport: @Sendable () -> Void

        /// The ChordPro type the app imports (Info.plist `UTImportedTypeDeclarations`).
        static let chordPro = UTType(
            importedAs: "dev.ryandsilva.segue.chordpro",
            conformingTo: .plainText,
        )

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(exportedContentType: chordPro) { drag in
                let copy = try drag.writeCopy(in: FileManager.default.temporaryDirectory)
                drag.onExport()
                return SentTransferredFile(copy, allowAccessingOriginalFile: false)
            }
            .suggestedFileName { $0.fileName }
        }

        /// Writes the song to a new folder under `base`, under its own file name.
        func writeCopy(in base: URL) throws -> URL {
            let folder = base.appending(
                path: "Segue Drag \(UUID().uuidString)",
                directoryHint: .isDirectory,
            )
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: fileName, directoryHint: .notDirectory)
            try read().write(to: copy, options: .atomic)
            return copy
        }
    }

    extension LibrarySession {
        /// The drag item for `record`; nil while a show is up (R109: nothing about the library
        /// may disturb the live view).
        func dragOut(_ record: SongRecord) -> SongFileDrag? {
            guard !library.isPerforming else { return nil }
            let source = root.url.appending(path: record.relativePath)
            let fileSystem = stores.fileSystem
            let services = library.services
            return SongFileDrag(
                fileName: source.lastPathComponent,
                read: { try fileSystem.readData(at: source) },
                onExport: {
                    Task { @MainActor in services.record(.featureUsed(.songDragOut, .library)) }
                },
            )
        }
    }

    extension View {
        /// Lets this row drag out as `drag`'s file; plain when there is none.
        @ViewBuilder
        func songDragOut(_ drag: SongFileDrag?, title: String) -> some View {
            if let drag {
                draggable(drag) { DragPreview(title: title) }
            } else {
                self
            }
        }
    }
#endif
