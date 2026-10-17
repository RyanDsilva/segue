#if os(macOS)
    import Library
    import SwiftUI

    /// Root of the app's main window: the library chooser until a library is open, then the
    /// Library / Setlists split view.
    public struct SegueRootView: View {
        let app: AppModel

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
            // Quit / close with unsaved edits asks first.
            .background(UnsavedChangesWindowGuard(app: app))
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
            }
        }
    }

    /// The main window once a library is open: the sidebar (Library, Gig log, setlists,
    /// tags) beside the chosen destination (layout a: the library's song list and preview,
    /// a setlist's builder, or the gig log).
    struct MainView: View {
        let app: AppModel
        @Bindable var session: LibrarySession

        var body: some View {
            NavigationSplitView {
                MainSidebar(session: session)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            } detail: {
                detail
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { errorBanner }
            .liveModePresentations(app)
            .onChange(of: session.setlists.selection) { session.followSetlistSelection() }
            .onChange(of: session.setlists.setlists) { session.followSetlistSelection() }
            .alert(
                unsavedTitle,
                isPresented: isPromptingUnsaved,
                presenting: session.library.pendingNavigation,
            ) { _ in
                Button("Save") { resolve(.save) }
                    .keyboardShortcut(.defaultAction)
                Button("Discard Changes", role: .destructive) { resolve(.discard) }
                Button("Cancel", role: .cancel) { resolve(.cancel) }
            } message: { _ in
                Text("Your edits will be lost if you don’t save them.")
            }
            .alert(
                conflictTitle,
                isPresented: isShowingConflict,
                presenting: session.library.saveConflict,
            ) { conflict in
                conflictButtons(conflict.kind)
            } message: { conflict in
                Text(conflictMessage(conflict.kind))
            }
        }

        // MARK: Save conflict

        private var conflictTitle: String {
            let title = session.library.saveConflict?.songTitle ?? "Untitled"
            return switch session.library.saveConflict?.kind {
            case .deleted: "“\(title)” was deleted in another app"
            case .metadataChanged: "The metadata of “\(title)” changed in another app"
            case nil, .sourceChanged: "“\(title)” was changed in another app"
            }
        }

        private func conflictMessage(_ kind: SongConflict) -> String {
            switch kind {
            case .sourceChanged:
                "Nothing was saved. Reload shows the file as it is now (your edits are "
                    + "discarded), Overwrite replaces the other app’s changes with yours, and "
                    + "Save as Copy keeps both."
            case .deleted:
                "Nothing was saved. Save your edits as a new song, or keep editing."
            case .metadataChanged:
                "Nothing was saved. Reload shows the song as it is now (your edits are "
                    + "discarded); Save as Copy keeps your edits as a new song."
            }
        }

        @ViewBuilder
        private func conflictButtons(_ kind: SongConflict) -> some View {
            switch kind {
            case .sourceChanged:
                Button("Reload") { resolveConflict(.reload) }
                Button("Overwrite", role: .destructive) { resolveConflict(.overwrite) }
                Button("Save as Copy") { resolveConflict(.saveAsCopy) }
                    .keyboardShortcut(.defaultAction)
            case .deleted:
                Button("Save as New Song") { resolveConflict(.saveAsCopy) }
                    .keyboardShortcut(.defaultAction)
            case .metadataChanged:
                Button("Reload") { resolveConflict(.reload) }
                Button("Save as Copy") { resolveConflict(.saveAsCopy) }
                    .keyboardShortcut(.defaultAction)
            }
            Button("Keep Editing", role: .cancel) { resolveConflict(.cancel) }
        }

        private var isShowingConflict: Binding<Bool> {
            Binding(
                get: { session.library.saveConflict != nil },
                set: { isPresented in
                    if !isPresented, session.library.saveConflict != nil {
                        resolveConflict(.cancel)
                    }
                },
            )
        }

        private func resolveConflict(_ choice: LibraryViewModel.SaveConflictChoice) {
            Task { await session.library.resolveSaveConflict(choice) }
        }

        private var unsavedTitle: String {
            let title = session.library.pendingNavigation?.songTitle ?? "Untitled"
            return "Save changes to “\(title)”?"
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
                LibraryPane(model: session.library, setlists: session.setlists)
            case .gigLog:
                GigLogPane(model: session.gigLog)
            case let .setlist(id):
                if let setlist = session.setlists.setlist(id) {
                    SetlistBuilderView(
                        setlist: setlist,
                        model: session.setlists,
                        library: session.library,
                    ) { setlist, kind in
                        Task { await app.startShow(setlist, kind: kind) }
                    }
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

    /// Menu bar commands for the main window.
    public struct SegueCommands: Commands {
        let app: AppModel
        @Environment(\.openWindow) private var openWindow

        public init(app: AppModel) {
            self.app = app
        }

        public var body: some Commands {
            CommandGroup(after: .appInfo) {
                Button("Acknowledgements") {
                    openWindow(id: AcknowledgementsWindow.id)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Song") {
                    guard let session = app.session else { return }
                    if session.section == .library {
                        session.library.beginNewSong()
                    } else {
                        session.library.navigate {
                            session.section = .library
                            session.library.beginNewSong()
                        }
                    }
                }
                .keyboardShortcut("n")
                // Nothing in the main window may change while the stage is up.
                .disabled(app.session == nil || app.isPerforming)
            }
            CommandMenu("Library") {
                Button("Refresh") {
                    guard let session = app.session else { return }
                    Task { await session.library.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(app.session == nil || app.isPerforming)
                Button("Rebuild Index") {
                    guard let session = app.session else { return }
                    Task { await session.library.rebuildIndex() }
                }
                .disabled(app.session == nil || app.isPerforming)
                Divider()
                Button("Choose Library Folder…") {
                    let choose = { Task { await app.chooseLibrary() } }
                    if let session = app.session {
                        session.library.navigate { _ = choose() }
                    } else {
                        _ = choose()
                    }
                }
                .disabled(app.isPerforming)
            }
        }
    }
#endif
