#if os(macOS)
    import Library
    import Setlists
    import Shows
    import SwiftUI

    /// Setlist (WS2a 3.5.3, A33 b): Start Show and Rehearse for the shown builder, New
    /// Setlist…, Add Selected Song(s) to Setlist ▸ (a keyboard and VoiceOver path for adding
    /// songs without dragging), and set building (R84, R85): Pick Songs / Arrange Set,
    /// Insert Break, Add Song by Name (P8-5, the set composer), Arrange Sections… (P3-16), and
    /// Move Up / Move Down for Arrange's selected rows.
    struct SetlistCommands: Commands {
        let app: AppModel
        @FocusedValue(\.focusedSongID) private var focusedSongID
        @FocusedValue(\.arrangeListFocused) private var arrangeListFocused

        var body: some Commands {
            CommandMenu("Setlist") {
                Button(MenuShortcuts.startShow.title) { start(.gig) }
                    .keyboardShortcut(MenuShortcuts.startShow)
                    .disabled(startableSetlist == nil)
                Button(MenuShortcuts.rehearse.title) { start(.rehearsal) }
                    .keyboardShortcut(MenuShortcuts.rehearse)
                    // While Arrange Sections is open its "Rehearse this" owns ⌥⌘↩ (P8-3 6.6).
                    .disabled(startableSetlist == nil || app.session?.setlists.arranging != nil)
                Divider()
                Button(MenuShortcuts.newSetlist.title) { app.session?.isNamingNewSetlist = true }
                    .keyboardShortcut(MenuShortcuts.newSetlist)
                    .disabled(app.session == nil || app.isPerforming || app.isMainWindowBusy)
                if let session = app.session, let songs = selectedSongs, songs.count > 1 {
                    AddSongsToSetlistMenu(
                        title: "Add Selected Songs to Setlist",
                        session: session,
                        songIDs: songs,
                    )
                } else if let session = app.session, let song = selectedSong {
                    AddToSetlistMenu(
                        title: "Add Selected Song to Setlist",
                        session: session,
                        songID: song,
                    )
                } else {
                    Button("Add Selected Song to Setlist") {}
                        .disabled(true)
                }
                Divider()
                buildingItems
            }
        }

        @ViewBuilder private var buildingItems: some View {
            let builder = editableBuilder
            Button(MenuShortcuts.pickSongs.title) { setMode(.pick) }
                .keyboardShortcut(MenuShortcuts.pickSongs)
                .disabled(shownBuilder == nil)
            Button(MenuShortcuts.arrangeSet.title) { setMode(.arrange) }
                .keyboardShortcut(MenuShortcuts.arrangeSet)
                .disabled(shownBuilder == nil)
            Button(MenuShortcuts.insertBreak.title) {
                guard let builder else { return }
                Task { await builder.model.insertBreak(in: builder.setlist.id) }
            }
            .keyboardShortcut(MenuShortcuts.insertBreak)
            .disabled(builder == nil)
            Button(MenuShortcuts.addSongByName.title) {
                builder?.model.composer.requestFocus()
            }
            .keyboardShortcut(MenuShortcuts.addSongByName)
            .disabled(builder == nil)
            Button(MenuShortcuts.arrangeSections.title) {
                shownBuilder?.model.arrangeSelectedSlot()
            }
            .keyboardShortcut(MenuShortcuts.arrangeSections)
            .disabled(shownBuilder?.model.arrangeableSelection == nil
                || shownBuilder?.model.builderMode != .arrange)
            Button(MenuShortcuts.moveUp.title) { move(-1) }
                .keyboardShortcut(MenuShortcuts.moveUp)
                .disabled(!canMove(-1))
            Button(MenuShortcuts.moveDown.title) { move(1) }
                .keyboardShortcut(MenuShortcuts.moveDown)
                .disabled(!canMove(1))
        }

        /// The shown builder's setlist and its model, when nothing covers the main window.
        private var shownBuilder: (setlist: Setlist, model: SetlistsViewModel)? {
            guard let session = app.session, let setlist = app.shownSetlist, !app.isPerforming,
                  !app.isMainWindowBusy
            else { return nil }
            return (setlist, session.setlists)
        }

        /// `shownBuilder` when its setlist can be edited.
        private var editableBuilder: (setlist: Setlist, model: SetlistsViewModel)? {
            guard let builder = shownBuilder, builder.setlist.readOnly == nil else { return nil }
            return builder
        }

        private func setMode(_ mode: BuilderMode) {
            shownBuilder?.model.builderMode = mode
        }

        /// Move Up / Move Down act only while Arrange's set list has keyboard focus, so ⌥↑
        /// and ⌥↓ keep their text meaning in every field.
        private func canMove(_ delta: Int) -> Bool {
            guard arrangeListFocused == true, let builder = editableBuilder,
                  builder.model.builderMode == .arrange
            else { return false }
            return builder.model.canMoveSelection(in: builder.setlist.id, by: delta)
        }

        private func move(_ delta: Int) {
            guard canMove(delta), let builder = editableBuilder else { return }
            Task { await builder.model.moveSelection(in: builder.setlist.id, by: delta) }
        }

        /// The shown builder's setlist when it can start: not performing or starting, nothing
        /// up in the main window, and at least one of its songs still in the library.
        private var startableSetlist: Setlist? {
            guard let session = app.session, let setlist = app.shownSetlist, !app.isPerforming,
                  !app.isStartingShow, !app.isMainWindowBusy,
                  setlist.entries.contains(where: {
                      $0.songId.flatMap(session.library.song(id:)) != nil
                  })
            else { return nil }
            return setlist
        }

        private func start(_ kind: ShowKind) {
            guard let setlist = startableSetlist else { return }
            // `startShow` saves the open editor first, as the builder's buttons do.
            Task { await app.startShow(setlist, kind: kind) }
        }

        private var selectedSong: SongID? {
            guard !app.isMainWindowBusy else { return nil }
            return app.menuSong(focused: focusedSongID)
        }

        /// The Library list's multi-selection while the list has focus.
        private var selectedSongs: [SongID]? {
            guard focusedSongID != nil, !app.isMainWindowBusy, !app.isPerforming,
                  let library = app.session?.library
            else { return nil }
            return library.selectedSongs
        }
    }

    /// Add to Setlist ▸: one item per setlist in sidebar order. A setlist that already holds
    /// the song is checked and disabled (a song appears at most once per setlist), and so is
    /// a read-only one. Shared by the Setlist menu, the song row's context menu and the
    /// detail pane's "…" menu.
    struct AddToSetlistMenu: View {
        var title = "Add to Setlist"
        let session: LibrarySession
        let songID: SongID

        var body: some View {
            Menu(title) {
                if session.setlists.setlists.isEmpty {
                    Button("No Setlists") {}
                        .disabled(true)
                }
                ForEach(session.setlists.setlists) { setlist in
                    // A checkmark (state on), dimmed, when the setlist already holds the
                    // song: VoiceOver reads it as checked and dimmed.
                    let holdsSong = setlist.contains(songID)
                    Toggle(setlist.name, isOn: Binding(
                        get: { holdsSong },
                        set: { _ in session.addSong(songID, to: setlist.id) },
                    ))
                    .disabled(holdsSong || setlist.readOnly != nil)
                }
            }
            .accessibilityIdentifier(AccessibilityID.addToSetlistMenu)
        }
    }
#endif
