#if os(macOS)
    import AppKit
    import SwiftUI

    /// What's New (WS2b 4.3), direction A "Notes" (R52): the app icon beside the title, each
    /// release's title, date and summary, then one row per highlight with a word badge
    /// ("New", "Improved", "Fixed") and "Learn More" when it has a help page. Links open in the
    /// browser. Continue, Esc or closing all dismiss it.
    struct WhatsNewSheet: View {
        let content: WhatsNewContent
        let workspace: any WorkspaceActions
        let onDismiss: () -> Void
        /// The rows' natural height, so short notes need no scroll and long ones scroll.
        @State private var notesHeight: CGFloat = 0

        static let width: CGFloat = 560
        /// Fits the widest badge, "Improved".
        static let badgeColumn: CGFloat = 72
        /// The notes scroll past this (the sheet stays on a 13-inch screen).
        static let maxNotesHeight: CGFloat = 440

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 22)
                ScrollView {
                    notes
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            notesHeight = $0
                        }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(notesHeight, 1), Self.maxNotesHeight))
                footer
                    .padding(.top, 18)
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .frame(width: Self.width)
            .background(Theme.color.ground)
            .onExitCommand(perform: onDismiss)
        }

        private var header: some View {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                Text(content.title)
                    .font(SchibstedGrotesk.extraBold.font(size: 26))
                    .tracking(Theme.tracking.title * 26)
                    .foregroundStyle(Theme.color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.whatsNewTitle)
            }
        }

        private var notes: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.releases.enumerated()), id: \.element.id) { index, release in
                    WhatsNewRelease(release: release, workspace: workspace)
                        .padding(.top, index == 0 ? 0 : 18)
                }
                if content.overflow > 0 {
                    Button(content.overflow == 1 ? uiString("and 1 more change")
                        : "and \(content.overflow) more changes")
                    {
                        workspace.open(SegueLinks.changelog)
                    }
                    .buttonStyle(.appLink)
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .padding(.leading, Self.badgeColumn + 12)
                    .padding(.top, 4)
                    .accessibilityIdentifier(AccessibilityID.whatsNewMore)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var footer: some View {
            HStack(alignment: .firstTextBaseline) {
                Button(uiString("All Release Notes")) { workspace.open(SegueLinks.changelog) }
                    .buttonStyle(.appLink)
                    .font(SchibstedGrotesk.semiBold.font(size: 13))
                    .accessibilityIdentifier(AccessibilityID.whatsNewAllNotes)
                Spacer()
                Button(action: onDismiss) {
                    Text("Continue", bundle: #bundle).frame(minWidth: 76)
                }
                .buttonStyle(.seguePrimary)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AccessibilityID.whatsNewContinue)
            }
        }
    }

    /// One release: title and date, summary, then its highlight rows.
    private struct WhatsNewRelease: View {
        let release: Changelog.Release
        let workspace: any WorkspaceActions

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(release.title)
                        .font(SchibstedGrotesk.bold.font(size: 17))
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(release.displayDate)
                        .font(SchibstedGrotesk.bold.font(size: 13))
                        .foregroundStyle(Theme.color.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.whatsNewRelease(release.version))
                if let summary = release.summary {
                    Text(summary)
                        .font(SchibstedGrotesk.medium.font(size: 14))
                        .foregroundStyle(Theme.color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(release.highlights.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.color.line)
                                .frame(height: 1)
                                .padding(.leading, WhatsNewSheet.badgeColumn + 12)
                                .accessibilityHidden(true)
                        }
                        WhatsNewRow(highlight: item, workspace: workspace)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    /// A highlight: the word badge, the sentence, and "Learn More" when there is a page.
    private struct WhatsNewRow: View {
        let highlight: Changelog.Highlight
        let workspace: any WorkspaceActions

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(highlight.kind.label)
                    .font(SchibstedGrotesk.bold.font(size: 12))
                    .foregroundStyle(Theme.color.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1.5)
                    .overlay(Capsule().strokeBorder(Theme.color.controlBorder, lineWidth: 1))
                    .fixedSize()
                    .frame(width: WhatsNewSheet.badgeColumn, alignment: .leading)
                    .accessibilityIdentifier(AccessibilityID.whatsNewBadge)
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlight.text)
                        .font(SchibstedGrotesk.medium.font(size: 15))
                        .foregroundStyle(Theme.color.ink)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = highlight.helpURL {
                        Button(uiString("Learn More")) { workspace.open(url) }
                            .buttonStyle(.appLink)
                            .font(SchibstedGrotesk.semiBold.font(size: 13))
                            .accessibilityLabel(uiString("Learn More: \(highlight.text)"))
                            .accessibilityIdentifier(AccessibilityID.whatsNewLearnMore)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.whatsNewRow)
        }
    }
#endif
