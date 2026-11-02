#if os(macOS)
    import Library
    import Setlists
    import SwiftUI

    extension LibrarySession {
        /// Add to Setlist with several songs selected (R84): adds them in list order,
        /// skipping songs already in the setlist, as one undo step, and says what happened
        /// ("Added 7 songs to Friday, 2 were already in the set").
        func addSongs(_ songIDs: [SongID], to setlistID: SetlistID) {
            Task {
                await library.flushEditor()
                let name = setlists.setlist(setlistID)?.name ?? "the setlist"
                let result = await setlists.addSongs(songIDs, to: setlistID)
                library.flash(Self.addedMessage(result, setlistName: name))
            }
        }

        /// "Added 7 songs to Friday, 2 were already in the set."
        static func addedMessage(_ result: (added: Int, skipped: Int), setlistName: String)
            -> String
        {
            let songs = result.added == 1 ? "1 song" : "\(result.added) songs"
            guard result.added > 0 else {
                return result.skipped == 1 ? "That song is already in \(setlistName)."
                    : "Those songs are already in \(setlistName)."
            }
            switch result.skipped {
            case 0: return "Added \(songs) to \(setlistName)."
            case 1: return "Added \(songs) to \(setlistName), 1 was already in the set."
            default:
                return "Added \(songs) to \(setlistName), \(result.skipped) were already in "
                    + "the set."
            }
        }
    }

    /// Add to Setlist ▸ for a multi-selection: one item per setlist. A setlist that already
    /// holds every selected song is checked and disabled, and so is a read-only one.
    struct AddSongsToSetlistMenu: View {
        var title = "Add to Setlist"
        let session: LibrarySession
        let songIDs: [SongID]

        var body: some View {
            Menu(title) {
                if session.setlists.setlists.isEmpty {
                    Button(uiString("No Setlists")) {}
                        .disabled(true)
                }
                ForEach(session.setlists.setlists) { setlist in
                    let holdsAll = songIDs.allSatisfy(setlist.contains)
                    Toggle(setlist.name, isOn: Binding(
                        get: { holdsAll },
                        set: { _ in session.addSongs(songIDs, to: setlist.id) },
                    ))
                    .disabled(holdsAll || setlist.readOnly != nil)
                }
            }
            .accessibilityIdentifier(AccessibilityID.addToSetlistMenu)
        }
    }

    /// The detail pane while several songs are selected: how many, and Add to Setlist.
    struct MultiSelectionPane: View {
        let session: LibrarySession
        let songIDs: [SongID]

        var body: some View {
            VStack(spacing: 14) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(Theme.color.muted)
                    .accessibilityHidden(true)
                Text("\(songIDs.count) songs selected", bundle: #bundle)
                    .font(Theme.font.sectionHeading)
                    .foregroundStyle(Theme.color.ink)
                Text("⌘-click to add or remove a song, ⇧-click to select a range.", bundle: #bundle)
                    .font(Theme.font.body)
                    .foregroundStyle(Theme.color.muted)
                AddSongsToSetlistMenu(session: session, songIDs: songIDs)
                    .menuStyle(.button)
                    .fixedSize()
                    .padding(.top, 4)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.color.ground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.multiSelection)
        }
    }
#endif
