#if os(macOS)
    import Foundation
    import Plugins
    import SwiftUI

    /// The review header's one quiet source line (P9-4 spec 11.6; R117's design otherwise
    /// unchanged): "From <host>" as a link to the page, or the plugin's own attribution
    /// ("From <site> · ver 3 · ★4.8", "Lyrics from <source>"), plus how it was read. Only a
    /// web page or search result has one; it is never stored (R179).
    struct ReviewSourceLine: View {
        let line: Content
        let open: () -> Void

        /// The line's parts, from the item's provenance (pure, so tests read it).
        struct Content: Equatable {
            /// The linked part.
            var source: String
            /// The quiet notes after it, each preceded by " - ".
            var notes: [String]
            /// R194: the title and Movie / Album split is a guess to check.
            var titleFlag: String?

            init(_ provenance: Provenance, titleUncertain: Bool) {
                let host = provenance.sourceURL.host(percentEncoded: false)
                    .map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
                source = provenance.attribution ?? String(
                    format: uiString("From %@"),
                    host,
                )
                var notes: [String] = []
                if provenance.fellBack {
                    notes.append(uiString("read with the general page reader"))
                }
                if provenance.romanized {
                    notes.append(uiString("converted from Devanagari"))
                }
                self.notes = notes
                titleFlag = titleUncertain
                    ? uiString("check where the title and Movie / Album split") : nil
            }

            /// The whole line as one string (VoiceOver, tests).
            var text: String {
                ([source] + notes + [titleFlag].compactMap(\.self)).joined(separator: " - ")
            }
        }

        var body: some View {
            HStack(spacing: 0) {
                Button(action: open) {
                    Text(verbatim: line.source).underline()
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(uiString("Open the page in your browser"))
                ForEach(line.notes, id: \.self) { note in
                    Text(verbatim: " - " + note)
                }
                if let flag = line.titleFlag {
                    Text(verbatim: " - ")
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                        .padding(.trailing, 4)
                    Text(verbatim: flag)
                        .foregroundStyle(Theme.color.ink)
                }
            }
            .font(SchibstedGrotesk.medium.font(size: 12.5))
            .foregroundStyle(Theme.color.muted)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(line.text)
            .accessibilityIdentifier(AccessibilityID.reviewSourceLine)
        }
    }
#endif
