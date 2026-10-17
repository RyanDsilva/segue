import ChordPro
import SwiftUI

/// A rendered song on paper: title, artist and performance line, then the body. Used by
/// the song detail pane and the editor preview.
struct SongPageView: View {
    let document: SongDocument
    /// Shown when the document has no title yet.
    var fallbackTitle = "Untitled"

    var body: some View {
        let metadata = document.metadata
        let sections = document.displaySections
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(Theme.font.title)
                    .tracking(Theme.tracking.title * 28)
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.songTitle)
                let subtitle = [SongSummary.artist(metadata), SongSummary.performanceLine(metadata)]
                    .compactMap(\.self)
                    .joined(separator: "  ·  ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.font.body)
                        .foregroundStyle(Theme.color.muted)
                }
            }
            if sections.isEmpty {
                Text("No lyrics yet.")
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
            } else {
                SongSheetView(sections: sections, style: .preview)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private var title: String {
        let title = document.metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        return title.isEmpty ? fallbackTitle : title
    }
}
