#if os(macOS)
    import Library
    import SwiftUI

    /// What an import did, at the bottom of the window (WS2a 3.2): "Imported 3 songs.",
    /// "Imported 3 songs. 1 skipped." or "No songs imported", with Details listing every
    /// skipped file and why (and any file converted to UTF-8). Laid out like the error
    /// banner, with a neutral icon: an import is not an error.
    struct ImportSummaryBar: View {
        let summary: ImportSummary
        let onDismiss: () -> Void
        @State private var isShowingDetails = false

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                Text(Self.headline(summary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.importSummary)
                if !summary.skipped.isEmpty || !summary.converted.isEmpty {
                    Button(uiString("Details")) { isShowingDetails = true }
                        .buttonStyle(.segueSecondary)
                        .controlSize(.small)
                        .accessibilityIdentifier(AccessibilityID.importSummaryDetails)
                        .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
                            ImportDetailsList(summary: summary)
                        }
                }
                Button(uiString("Dismiss"), action: onDismiss)
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }

        /// "Imported 3 songs. 1 skipped."
        static func headline(_ summary: ImportSummary) -> String {
            let imported = summary.imported.count
            let skipped = summary.skipped.count
            guard imported > 0 else { return "No songs imported" }
            let songs = imported == 1 ? "Imported 1 song." : "Imported \(imported) songs."
            return skipped == 0 ? songs : "\(songs) \(skipped) skipped."
        }
    }

    /// Every skipped file with its reason, then the files converted to UTF-8 (the same
    /// style as the library's load issues).
    private struct ImportDetailsList: View {
        let summary: ImportSummary

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !summary.skipped.isEmpty {
                        Text(uiString("These files were not imported. They are left as they were."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(summary.skipped.enumerated()), id: \.offset) { _, skip in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skip.fileName)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                            Text(skip.reason)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !summary.converted.isEmpty {
                        Text("Converted to UTF-8", bundle: #bundle)
                            .font(.callout.weight(.semibold))
                            .padding(.top, summary.skipped.isEmpty ? 0 : 4)
                        ForEach(summary.converted, id: \.self) { line in
                            Text(line)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(14)
                .frame(width: 360, alignment: .leading)
            }
            .frame(maxHeight: 420)
        }
    }
#endif
