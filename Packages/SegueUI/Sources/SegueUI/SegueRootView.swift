#if os(macOS)
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

    /// The main window once a library is open: sidebar (Library, Setlists), list, detail.
    struct MainView: View {
        let app: AppModel
        @Bindable var session: LibrarySession

        var body: some View {
            NavigationSplitView {
                List(selection: $session.sidebarSelection) {
                    Label("Library", systemImage: "music.note.list")
                        .tag(LibrarySession.Section.library)
                        .accessibilityIdentifier(AccessibilityID.sidebarLibrary)
                    Label("Setlists", systemImage: "list.number")
                        .tag(LibrarySession.Section.setlists)
                        .accessibilityIdentifier(AccessibilityID.sidebarSetlists)
                }
                .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 260)
            } content: {
                Group {
                    switch session.section {
                    case .library, nil:
                        SongListView(model: session.library, setlists: session.setlists)
                    case .setlists:
                        SetlistListView(model: session.setlists)
                    }
                }
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            } detail: {
                detail
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { errorBanner }
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
                LibraryDetailView(model: session.library)
            case .setlists:
                if let setlist = session.setlists.selected {
                    SetlistDetailView(
                        setlist: setlist,
                        model: session.setlists,
                        library: session.library,
                    ) { setlist in
                        app.perform(setlist)
                        StageWindowController.shared.present(app)
                    }
                } else {
                    ContentUnavailableView(
                        "No Setlist Selected",
                        systemImage: "list.number",
                        description: Text("Choose a setlist, or create a new one."),
                    )
                }
            }
        }

        @ViewBuilder private var errorBanner: some View {
            if let message = session.library.errorMessage ?? session.setlists.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text(message)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss") {
                        session.library.errorMessage = nil
                        session.setlists.errorMessage = nil
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
                .disabled(app.session == nil)
            }
            CommandMenu("Library") {
                Button("Refresh") {
                    guard let session = app.session else { return }
                    Task { await session.library.refresh() }
                }
                .keyboardShortcut("r")
                .disabled(app.session == nil)
                Button("Rebuild Index") {
                    guard let session = app.session else { return }
                    Task { await session.library.rebuildIndex() }
                }
                .disabled(app.session == nil)
                Divider()
                Button("Choose Library Folder…") {
                    let choose = { Task { await app.chooseLibrary() } }
                    if let session = app.session {
                        session.library.navigate { _ = choose() }
                    } else {
                        _ = choose()
                    }
                }
            }
        }
    }
#endif
