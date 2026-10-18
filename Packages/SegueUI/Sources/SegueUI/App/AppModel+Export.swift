#if os(macOS)
    import AppKit
    import Foundation
    import Library
    import UniformTypeIdentifiers

    // WS2b 4.8: File > Export Library Archive… and Settings > Data: the save panel, then the
    // archive written off the main actor. Restore is not in 0.5 (B-23).

    public extension AppModel {
        /// Export is possible: a library is open, no show, no export already running.
        var canExportArchive: Bool {
            session != nil && !isPerforming && !isStartingShow && !isExporting
        }

        /// Asks where to save `Segue Library YYYY-MM-DD.zip` (or uses `-SegueExportPath`),
        /// then writes it. A failure leaves nothing at the destination and shows the banner.
        func exportLibraryArchive() async {
            guard canExportArchive, let session else { return }
            let archive = LibraryArchive(
                fileSystem: dependencies.fileSystem,
                clock: dependencies.clock,
            )
            guard let destination = await exportDestination(named: archive.defaultFileName)
            else { return }
            isExporting = true
            defer { isExporting = false }
            let root = session.root
            do {
                try await Task.detached(priority: .userInitiated) {
                    try archive.export(root: root, to: destination)
                }.value
                session.library.flash("Exported “\(destination.lastPathComponent)”")
            } catch {
                session.library.errorMessage = "Segue could not export the library "
                    + "(\(UserMessage.describe(error)))."
            }
        }

        /// The save panel (default name, `.zip` only), or the Debug test path.
        private func exportDestination(named name: String) async -> URL? {
            if let path = polish.launch.exportPath {
                return path
            }
            let panel = NSSavePanel()
            panel.title = "Export Library Archive"
            panel.prompt = "Export"
            panel.nameFieldStringValue = name
            panel.allowedContentTypes = [.zip]
            panel.canCreateDirectories = true
            panel.directoryURL = URL.desktopDirectory
            let response: NSApplication.ModalResponse = if let window = NSApp.keyWindow {
                await panel.beginSheetModal(for: window)
            } else {
                panel.runModal()
            }
            return response == .OK ? panel.url : nil
        }
    }
#endif
