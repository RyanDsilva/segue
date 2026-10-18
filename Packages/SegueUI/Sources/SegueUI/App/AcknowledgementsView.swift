#if os(macOS)
    import SwiftUI

    /// Identity of the Acknowledgements window scene (Segue > Acknowledgements).
    public enum AcknowledgementsWindow {
        public static let id = "segue.acknowledgements"
    }

    /// Third-party software and fonts bundled in Segue, with their full licence texts
    /// (the SIL OFL 1.1 requires the font licence to ship with the app; MIT requires the
    /// copyright notices).
    public struct AcknowledgementsView: View {
        struct Credit: Identifiable {
            let name: String
            let summary: String
            let licence: String
            let source: String
            /// Licence text resource: (subdirectory, file name without extension).
            let resource: (folder: String, name: String)

            var id: String {
                name
            }
        }

        static let credits = [
            Credit(
                name: "Schibsted Grotesk",
                summary: "Typeface used throughout Segue.",
                licence: "SIL Open Font License 1.1",
                source: "github.com/schibsted/schibsted-grotesk",
                resource: ("Fonts", "OFL"),
            ),
            Credit(
                name: "GRDB",
                summary: "SQLite toolkit behind the song search index.",
                licence: "MIT License",
                source: "github.com/groue/GRDB.swift",
                resource: ("Licenses", "GRDB"),
            ),
            Credit(
                name: "Tonic",
                summary: "Music theory types for keys and chords.",
                licence: "MIT License",
                source: "github.com/AudioKit/Tonic",
                resource: ("Licenses", "Tonic"),
            ),
            Credit(
                name: "Sentry",
                summary: "Crash and hang reports, sent only if you allow them.",
                licence: "MIT License",
                source: "github.com/getsentry/sentry-cocoa",
                resource: ("Licenses", "Sentry"),
            ),
        ]

        public init() {}

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Acknowledgements")
                            .font(Theme.font.title)
                            .tracking(Theme.tracking.title * 28)
                            .foregroundStyle(Theme.color.ink)
                        Text("Segue is built with these open-source projects. Thank you.")
                            .font(Theme.font.body)
                            .foregroundStyle(Theme.color.muted)
                    }
                    ForEach(Self.credits) { credit in
                        CreditView(credit: credit)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.color.ground)
            .accessibilityIdentifier(AccessibilityID.acknowledgements)
        }

        /// The bundled licence text for `credit`, or nil if the resource is missing.
        static func licenceText(_ credit: Credit) -> String? {
            let url = Theme.bundle.url(
                forResource: credit.resource.name,
                withExtension: "txt",
                subdirectory: credit.resource.folder,
            ) ?? Theme.bundle.url(forResource: credit.resource.name, withExtension: "txt")
            return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
    }

    private struct CreditView: View {
        let credit: AcknowledgementsView.Credit
        @State private var isExpanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(credit.name)
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                Text(credit.summary)
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.ink)
                Text("\(credit.licence) · \(credit.source)")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .textSelection(.enabled)
                if let text = AcknowledgementsView.licenceText(credit) {
                    DisclosureGroup("Licence text", isExpanded: $isExpanded) {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.color.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.ink)
                }
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .contain)
        }
    }
#endif
