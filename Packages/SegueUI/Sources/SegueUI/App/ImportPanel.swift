#if os(macOS)
    import AppKit
    import Library
    import UniformTypeIdentifiers

    /// Where File > Import Songs… gets its files (WS2a 3.2, 3.12): the open panel, or fixed
    /// paths in E2E (sandboxed open panels run out of process and are not drivable from
    /// XCUITest).
    @MainActor
    public protocol ImportPanel: AnyObject {
        /// The files and folders the user chose; empty when cancelled.
        func chooseFiles() async -> [URL]
    }

    /// `NSOpenPanel`: several files and folders of the accepted types.
    @MainActor
    public final class OpenPanelImportPanel: ImportPanel {
        public init() {}

        public func chooseFiles() async -> [URL] {
            let panel = NSOpenPanel()
            panel.title = "Import Songs"
            panel.prompt = "Import"
            panel.message = "Choose ChordPro or text files, or folders of them."
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = SongFileTypes.importExtensions.compactMap {
                UTType(filenameExtension: $0)
            } + [.folder]
            let response = await withCheckedContinuation { continuation in
                panel.begin { response in
                    continuation.resume(returning: response)
                }
            }
            return response == .OK ? panel.urls : []
        }
    }

    #if DEBUG
        /// Test-only (`-SegueImportPanelPaths <p1:p2>`, Debug builds): "chooses" these paths.
        @MainActor
        public final class FixedImportPanel: ImportPanel {
            public let urls: [URL]

            public init(urls: [URL]) {
                self.urls = urls
            }

            public func chooseFiles() async -> [URL] {
                urls
            }
        }
    #endif
#endif
