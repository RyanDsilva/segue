#if os(macOS)
    import Editing
    import Foundation
    import Library
    import Support

    /// The first open of a library with this build (P8-8 sections 5.7, 5.8, R173): the old
    /// `timings/` folder goes to the Trash with a one-time note, and the `{duration}`
    /// cleanup is offered once. Nothing in any chart changes unless the user says Remove.
    extension LibrarySession {
        /// "Song length is now worked out from tempo. Remove the old length lines from N songs?"
        static func durationOfferText(_ count: Int) -> String {
            "Song length is now worked out from tempo. Remove the old length lines from "
                + (count == 1 ? "1 song?" : "\(count) songs?")
        }

        /// Runs the one-time steps after the stores opened. `isCopy`: the folder was a Finder
        /// copy of another library and was just given its own identity (P9-6 5.2).
        func runUpgradeSteps(fileSystem: any FileSystem, isCopy: Bool = false) {
            if isCopy {
                upgradeNote = LibraryNote(title: LibraryState.copyNote)
            }
            let moved = LibraryUpgrade.moveTimingsToTrash(
                root: root,
                fileSystem: fileSystem,
                trash: { _ = try fileSystem.trashItem(at: $0) },
            )
            if moved {
                upgradeNote = LibraryNote(
                    title: LibraryUpgrade.timingsNote,
                    message: "You can restore it from the Trash.",
                )
            }
            let state = LibraryUpgrade.state(root: root, fileSystem: fileSystem)
            let count = LibraryUpgrade.songsWithDurationLines(library.catalog).count
            if !state.durationCleanupOffered, count > 0 {
                durationOffer = count
            }
        }

        /// The alert's Remove or Not Now: the offer leaves the alert at once (so closing the
        /// alert never reads as a second, "Not Now" answer), then is answered.
        func chooseDurationOffer(remove: Bool) {
            durationOffer = nil
            Task { await answerDurationOffer(remove: remove) }
        }

        /// Not Now or Remove: the offer is recorded as made (it never appears again for this
        /// library); Remove deletes every `{duration}` line, one undo step.
        func answerDurationOffer(remove: Bool) async {
            durationOffer = nil
            var state = LibraryUpgrade.state(root: root, fileSystem: stores.fileSystem)
            state.durationCleanupOffered = true
            try? LibraryUpgrade.save(state, root: root, fileSystem: stores.fileSystem)
            if remove {
                await library.removeDurationLines()
            }
        }
    }

    /// A one-time note shown in the upgrade alert (OK only).
    public struct LibraryNote: Equatable, Sendable {
        public var title: String
        public var message: String?

        public init(title: String, message: String? = nil) {
            self.title = title
            self.message = message
        }
    }

    extension LibraryViewModel {
        /// The songs Remove Old Length Lines would change.
        var songsWithDurationLines: [SongID] {
            LibraryUpgrade.songsWithDurationLines(catalog)
        }

        /// Deletes each `{duration}` line (with its line ending) and nothing else from every
        /// editable song: one library undo step for the whole batch.
        func removeDurationLines() async {
            let songs = songsWithDurationLines
            guard !songs.isEmpty else { return }
            undoManager?.beginUndoGrouping()
            for song in songs {
                await editSongSource(id: song, .removeDirectives(name: "duration"))
            }
            undoManager?.setActionName("Remove Old Length Lines")
            undoManager?.endUndoGrouping()
        }
    }
#endif

#if os(macOS)
    import SwiftUI

    /// The one-time notes of the first open with this build: the timings note (OK), then the
    /// `{duration}` cleanup offer (Remove / Not Now). One alert, the note first.
    struct LibraryUpgradeAlert: ViewModifier {
        let session: LibrarySession

        func body(content: Content) -> some View {
            content.alert(
                title,
                isPresented: Binding(
                    get: { session.upgradeNote != nil || session.durationOffer != nil },
                    set: { isPresented in
                        guard !isPresented else { return }
                        // Closed without a choice: the note is read; the offer is Not Now.
                        if session.upgradeNote != nil {
                            session.upgradeNote = nil
                        } else if session.durationOffer != nil {
                            Task { await session.answerDurationOffer(remove: false) }
                        }
                    },
                ),
            ) {
                if session.upgradeNote != nil {
                    // Closing the alert clears the note (the setter above). Clearing it here
                    // too made the setter see only the offer and answer it Not Now unseen.
                    Button("OK") {}
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Remove") { session.chooseDurationOffer(remove: true) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.durationCleanupRemove)
                    Button("Not Now", role: .cancel) { session.chooseDurationOffer(remove: false) }
                        .accessibilityIdentifier(AccessibilityID.durationCleanupNotNow)
                }
            } message: {
                if let note = session.upgradeNote {
                    if let message = note.message {
                        Text(message)
                    }
                } else {
                    Text("Only the {duration} lines are removed; nothing else in your charts "
                        + "changes. One Undo puts them back.")
                }
            }
        }

        private var title: String {
            if let note = session.upgradeNote {
                return note.title
            }
            return LibrarySession.durationOfferText(session.durationOffer ?? 0)
        }
    }

    extension AccessibilityID {
        static let durationCleanupRemove = "segue.library.durationCleanup.remove"
        static let durationCleanupNotNow = "segue.library.durationCleanup.notNow"
    }
#endif
