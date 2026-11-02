#if os(macOS)
    import Foundation
    import SwiftUI

    // P9-4 (Personal build only): the empty library's web import and Find Lyrics row and
    // dropped links. Both exist only when the app composed the plugin entries.

    extension View {
        /// Accepts dropped files and folders for import while import is possible; refused
        /// drops show no highlight. P9-4 spec 11.5 (Personal build only): a lone dropped
        /// `http(s)` link reads that page in the New Song sheet.
        func importDrop(model: LibraryViewModel, isTargeted: Binding<Bool>) -> some View {
            dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return model.importDroppedLink(urls) }
                guard model.canImport else { return false }
                Task { await model.importSongs(files) }
                return true
            } isTargeted: { targeted in
                isTargeted.wrappedValue = targeted && model.canImport
            }
        }
    }

    extension SongListView {
        /// P9-4 spec 11.2 (Personal build only): two link-style buttons under the first row.
        @ViewBuilder var personalImportRow: some View {
            if model.plugins.webImport != nil || model.plugins.songSearch != nil {
                HStack(spacing: 16) {
                    if model.plugins.webImport != nil {
                        Button(uiString("Import from a web page")) {
                            model.beginWebImport()
                        }
                        .accessibilityIdentifier(AccessibilityID.emptyLibraryWebImport)
                    }
                    if model.plugins.songSearch != nil {
                        Button(uiString("Find lyrics")) { model.beginSongSearch() }
                            .accessibilityIdentifier(AccessibilityID.emptyLibraryFindLyrics)
                    }
                }
                .buttonStyle(.link)
                .disabled(!model.canPaste)
            }
        }
    }

    extension LibraryViewModel {
        /// A dropped `http(s)` link (spec 11.5) reads that page in the New Song sheet; with
        /// no web import entry links are refused, as in the App Store build.
        func importDroppedLink(_ urls: [URL]) -> Bool {
            guard plugins.webImport != nil, canPaste, urls.count == 1,
                  let link = urls.first.flatMap({ LoneWebAddress.url(in: $0.absoluteString) })
            else { return false }
            beginWebImport(.address(link, .droppedLink))
            return true
        }
    }
#endif
