#if os(macOS)
    import AppKit
    import Library
    import SwiftUI

    /// Root of the app's main window: the library chooser until a library is open, then the
    /// Library / Setlists split view.
    public struct SegueRootView: View {
        /// The main window scene's identity.
        public static let windowID = "segue.main"

        let app: AppModel
        @Environment(\.openWindow) private var openWindow

        public init(app: AppModel) {
            self.app = app
        }

        public var body: some View {
            Group {
                switch app.state {
                case .starting:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .needsLibrary(reason):
                    LibraryChooserView(app: app, reason: reason)
                case let .opening(url):
                    ProgressView("Opening \(url.lastPathComponent)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .ready(session):
                    MainView(app: app, session: session)
                }
            }
            .task { await app.start() }
            // The consent prompt (WS3 4.2) once the library state has settled.
            .servicesPresentations(app)
            // A Dock click with no window open brings this window back (review risk F2).
            .onAppear {
                let openWindow = openWindow
                PendingEditsGuard.shared.reopenMainWindow = {
                    openWindow(id: Self.windowID)
                }
            }
            // Quit / close save pending edits first (and ask only if that fails).
            .background(PendingEditsWindowGuard(app: app))
        }
    }

    /// First launch (or lost access): pick or create the library folder.
    struct LibraryChooserView: View {
        let app: AppModel
        let reason: AppModel.NeedsLibraryReason

        var body: some View {
            VStack(spacing: 0) {
                Spacer(minLength: 32)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("Segue")
                        .font(Theme.font.display)
                        .tracking(Theme.tracking.display * 64)
                        .foregroundStyle(Theme.color.ink)
                        .accessibilityIdentifier(AccessibilityID.rootTitle)
                    Circle()
                        .fill(Theme.color.cue)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                Text(message)
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .padding(.top, 18)
                    .accessibilityIdentifier(AccessibilityID.chooserMessage)
                VStack(spacing: 10) {
                    Button {
                        Task { await app.createLibrary() }
                    } label: {
                        Text("Create Library in Music…")
                            .frame(minWidth: 240)
                    }
                    .buttonStyle(.seguePrimary)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier(AccessibilityID.chooserCreate)
                    Button {
                        Task { await app.chooseLibrary() }
                    } label: {
                        Text("Choose Existing Folder…")
                            .frame(minWidth: 240)
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.large)
                    .accessibilityIdentifier(AccessibilityID.chooserOpen)
                }
                .padding(.top, 32)
                Spacer(minLength: 32)
                Text("Songs are plain ChordPro files you can open in any editor.")
                    .font(Theme.font.label)
                    .foregroundStyle(Theme.color.muted)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.color.ground)
            // One continuous paper ground: no title or toolbar band above the wordmark.
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }

        private var message: String {
            switch reason {
            case .firstLaunch:
                "Choose where your songs live. We suggest a Segue folder in your Music folder."
            case let .accessLost(url):
                if let url {
                    "Segue can no longer open “\(url.lastPathComponent)”. "
                        + "Choose the library folder again."
                } else {
                    "Segue can no longer open your library folder. Choose it again."
                }
            case let .openFailed(message):
                "That folder could not be opened as a library: \(message)"
            case .inUseByAnotherCopy:
                AppModel.inUseMessage
            }
        }
    }

    /// The main window once a library is open: the sidebar (Library, Gig log, setlists,
    /// tags) beside the chosen destination (layout a: the library's song list and preview,
    /// a setlist's builder, or the gig log).
    struct MainView: View {
        let app: AppModel
        @Bindable var session: LibrarySession
        @Environment(\.undoManager) private var undoManager

        var body: some View {
            NavigationSplitView {
                MainSidebar(session: session)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            } detail: {
                detail
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    errorBanner
                    if let summary = session.library.importSummary {
                        ImportSummaryBar(summary: summary) {
                            session.library.dismissImportSummary()
                        }
                    }
                    transientBar
                }
            }
            .liveModePresentations(app)
            // Deletes, import and metadata edits undo through the window (Edit > Undo).
            .onAppear { session.undoManager = undoManager }
            .onChange(of: undoManager.map(ObjectIdentifier.init)) {
                session.undoManager = undoManager
            }
            .confirmationDialog(
                session.songTrashConfirmation?.headline ?? "",
                isPresented: isConfirmingSongTrash,
                titleVisibility: .visible,
                presenting: session.songTrashConfirmation,
            ) { _ in
                Button("Move to Trash", role: .destructive) {
                    session.resolveSongTrashConfirmation(moveToTrash: true)
                }
                .accessibilityIdentifier(AccessibilityID.songDeleteConfirm)
                Button("Cancel", role: .cancel) {
                    session.resolveSongTrashConfirmation(moveToTrash: false)
                }
                .keyboardShortcut(.defaultAction)
            } message: { confirmation in
                Text(confirmation.message)
            }
            .onChange(of: session.setlists.selection) { session.followSetlistSelection() }
            .onChange(of: session.setlists.setlists) { session.followSetlistSelection() }
            .alert(
                unsavedTitle,
                isPresented: isPromptingUnsaved,
                presenting: session.library.pendingNavigation,
            ) { _ in
                // The only unsaved-edits prompt left (autosave, WS2a 3.4): the save failed.
                Button("Save as Copy") { resolve(.saveAsCopy) }
                    .keyboardShortcut(.defaultAction)
                Button("Discard Edits", role: .destructive) { resolve(.discard) }
                Button("Cancel", role: .cancel) { resolve(.cancel) }
            } message: { _ in
                Text("Segue could not save them to the song’s file. Save them as a new song, "
                    + "or discard them.")
            }
        }

        private var isConfirmingSongTrash: Binding<Bool> {
            Binding(
                get: { session.songTrashConfirmation != nil },
                set: { isPresented in
                    if !isPresented, session.songTrashConfirmation != nil {
                        session.resolveSongTrashConfirmation(moveToTrash: false)
                    }
                },
            )
        }

        private var unsavedTitle: String {
            let title = session.library.pendingNavigation?.songTitle ?? "Untitled"
            return "Your edits to “\(title)” aren’t saved"
        }

        private var isPromptingUnsaved: Binding<Bool> {
            Binding(
                get: { session.library.pendingNavigation != nil },
                set: { isPresented in
                    // Dismissed without a button (should not happen): treat as Cancel.
                    if !isPresented, session.library.pendingNavigation != nil {
                        resolve(.cancel)
                    }
                },
            )
        }

        private func resolve(_ choice: LibraryViewModel.UnsavedChangesChoice) {
            Task { await session.library.resolvePendingNavigation(choice) }
        }

        @ViewBuilder private var detail: some View {
            switch session.section {
            case .library, nil:
                LibraryPane(session: session)
            case .gigLog:
                GigLogPane(model: session.gigLog) { id in
                    Task { await session.revealGig(id) }
                }
            case let .setlist(id):
                if let setlist = session.setlists.setlist(id) {
                    SetlistBuilderView(
                        setlist: setlist,
                        model: session.setlists,
                        library: session.library,
                        onReveal: { Task { await session.revealSetlist(id) } },
                        onStart: { setlist, kind in
                            Task { await app.startShow(setlist, kind: kind) }
                        },
                    )
                    .id(id)
                } else {
                    ContentUnavailableView(
                        "Setlist Not Found",
                        systemImage: "list.number",
                        description: Text("It may have been deleted. Choose another setlist."),
                    )
                }
            }
        }

        @ViewBuilder private var errorBanner: some View {
            if let message = session.library.errorMessage ?? session.setlists.errorMessage
                ?? session.gigLog.errorMessage
            {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text(message)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss") {
                        session.library.errorMessage = nil
                        session.setlists.errorMessage = nil
                        session.gigLog.errorMessage = nil
                    }
                    .buttonStyle(.segueSecondary)
                    .controlSize(.small)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    extension MainView {
        /// A short neutral confirmation in the bottom bar (File > Save outside the editor,
        /// Add to Setlist), gone after 1.5 s.
        @ViewBuilder var transientBar: some View {
            if let message = session.library.transientMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.color.muted)
                        .accessibilityHidden(true)
                    Text(message)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(AccessibilityID.transientMessage)
            }
        }
    }
#endif
