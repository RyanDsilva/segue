import Foundation
import Library

public extension LibraryViewModel {
    /// An autosave that found the song's files changed on disk since the editor opened
    /// them. Autosave waits until the user picks in the conflict bar.
    struct SaveConflict: Equatable {
        public let songID: SongID
        public let kind: SongConflict
        /// The title of the song being edited, for the prompt.
        public let songTitle: String
    }

    /// How the user answered the conflict bar.
    enum SaveConflictChoice {
        /// Drop the edits and edit the file as it is on disk now.
        case reload
        /// Write the edits over the file on disk (`.sourceChanged` only).
        case overwrite
        /// Keep the file on disk and save the edits as a new song.
        case saveAsCopy
    }
}

/// The revision an editor's text is based on, advanced by each successful save.
@MainActor
final class RevisionBox {
    var revision: SongRevision

    init(_ revision: SongRevision) {
        self.revision = revision
    }
}
