#if os(macOS)
    import Support
    import SwiftUI

    /// The file-sync folder warning (P9-6 5.4): a gentle, dismissible banner at the top of
    /// the library list while the library sits in iCloud Drive or a CloudStorage folder,
    /// until Don't Show Again (remembered per library ID in its `state.json`). Never a
    /// modal, never during a show.
    extension LibrarySession {
        /// Records the open folder's kind and whether its warning was dismissed before.
        func checkFolderKind(_ kind: LibraryFolderKind) {
            folderKind = kind
            fileSyncWarningDismissed = LibraryStateRecord.read(
                state,
                fileSystem: stores.fileSystem,
            )?
                .fileSyncWarningDismissed ?? false
        }

        /// Whether the banner is up (not while performing).
        var showsFileSyncWarning: Bool {
            folderKind.isFileSynced && !fileSyncWarningDismissed && !library.isPerforming
        }

        /// Don't Show Again: hides the banner for this library on this Mac. The banner goes
        /// at once; a failed write only means it comes back on the next open.
        func dismissFileSyncWarning() {
            fileSyncWarningDismissed = true
            var record = LibraryStateRecord.read(state, fileSystem: stores.fileSystem)
                ?? LibraryStateRecord()
            record.fileSyncWarningDismissed = true
            try? record.write(to: state, fileSystem: stores.fileSystem)
        }
    }

    /// The banner itself, styled like the editor's review banner (`FlaggedDefinesBanner`):
    /// the alternate surface with a hairline, a title and a muted detail line, and the
    /// actions below them so it fits the narrow list column.
    struct FileSyncWarningBanner: View {
        let session: LibrarySession
        @Environment(\.openGuide) private var openGuide

        var body: some View {
            if session.showsFileSyncWarning, let title = session.folderKind.warningTitle {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.icloud")
                            .foregroundStyle(Theme.color.cue)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(SchibstedGrotesk.semiBold.font(size: 14))
                                .foregroundStyle(Theme.color.ink)
                            Text(LibraryFolderKind.warningDetail)
                                .font(SchibstedGrotesk.medium.font(size: 13))
                                .foregroundStyle(Theme.color.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if let openGuide {
                            Button("Learn More") { openGuide(.fileSync) }
                                .accessibilityIdentifier(AccessibilityID.fileSyncLearnMore)
                        }
                        Button("Don't Show Again") { session.dismissFileSyncWarning() }
                            .accessibilityIdentifier(AccessibilityID.fileSyncDismiss)
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.color.surfaceAlt)
                .overlay(alignment: .bottom) { Hairline() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.fileSyncBanner)
            }
        }
    }

    extension AccessibilityID {
        static let fileSyncBanner = "segue.library.fileSync"
        static let fileSyncLearnMore = "segue.library.fileSync.learnMore"
        static let fileSyncDismiss = "segue.library.fileSync.dismiss"
        static let settingsFileSyncNote = "segue.settings.data.fileSync"
    }
#endif
