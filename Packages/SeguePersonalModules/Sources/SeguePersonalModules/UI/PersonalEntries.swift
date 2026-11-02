import Foundation
import Plugins
import SegueUI
import SwiftUI

@MainActor
public extension PersonalModules {
    /// The Personal build's UI entries (spec 4.3) over the plugins `register(into:)` put in
    /// `registry`: the New Song web field, Find Lyrics and Settings > Data's Clear Site Data.
    /// Empty when the registry holds none of this package's plugins.
    static func entries(registry: PluginRegistry) -> PluginEntries {
        guard let importer = registry.songImporters.lazy.compactMap({ $0 as? WebPageImporter })
            .first
        else { return PluginEntries() }
        let sources = registry.songSearchSources
        let services = importer.services
        return PluginEntries(
            webImport: WebImportEntry(
                field: { host in AnyView(WebImportFieldHost(importer: importer, host: host)) },
                settings: { AnyView(SiteDataSettings(clear: services.clearSiteData)) },
                fileExtensions: SavedPagePanel.extensions,
            ),
            songSearch: sources.isEmpty ? nil : SongSearchEntry { host in
                AnyView(FindLyricsHost(
                    sources: sources,
                    challenges: services.challenges,
                    host: host,
                ))
            },
        )
    }
}

/// Owns the web field's model for the life of the New Song sheet.
private struct WebImportFieldHost: View {
    let host: ImportHost
    @State private var model: WebImportModel

    init(importer: WebPageImporter, host: ImportHost) {
        self.host = host
        _model = State(initialValue: WebImportModel(importer: importer))
    }

    var body: some View {
        WebImportField(model: model, host: host)
    }
}

/// Owns the Find Lyrics model for the life of the sheet.
private struct FindLyricsHost: View {
    let host: ImportHost
    @State private var model: FindLyricsModel

    init(
        sources: [any SongSearchSource],
        challenges: (any ChallengeViewSource)?,
        host: ImportHost,
    ) {
        self.host = host
        _model = State(initialValue: FindLyricsModel(sources: sources, challenges: challenges))
    }

    var body: some View {
        FindLyricsSheet(model: model, host: host)
    }
}

/// Settings > Data > Web import (spec 8.6, R184): Clear Site Data removes the hidden view's
/// whole cookie store, so the next page that checks for a person asks again.
struct SiteDataSettings: View {
    let clear: @Sendable () async -> Void
    @State private var status: String?
    @State private var working = false

    var body: some View {
        LabeledContent("Site data") {
            Button("Clear Site Data") {
                working = true
                Task {
                    await clear()
                    working = false
                    status = "Cleared. The next page that checks for a person asks again."
                }
            }
            .disabled(working)
            .accessibilityIdentifier(AccessibilityID.clearSiteData)
        }
        Text(verbatim: status ?? "Cookies the hidden page loader keeps between imports, so a "
            + "check you completed is not asked again. No page or lyric is kept.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
