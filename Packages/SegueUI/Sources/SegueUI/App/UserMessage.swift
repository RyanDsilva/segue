import Foundation
import Library
import Setlists
import Shows

/// Turns errors into short, user-facing sentences.
enum UserMessage {
    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as LibraryError:
            describe(error)
        case let error as SetlistError:
            describe(error)
        case let error as ShowError:
            describe(error)
        case let error as any LocalizedError:
            error.errorDescription ?? error.localizedDescription
        default:
            (error as NSError).localizedDescription
        }
    }

    private static func describe(_ error: LibraryError) -> String {
        switch error {
        case .notOpen:
            "The library is not open."
        case .songNotFound:
            "That song is no longer in the library."
        case let .readOnly(_, reason):
            readOnlyText(reason)
        case let .conflict(_, conflict):
            conflictText(conflict)
        }
    }

    /// Why a save was refused because the song's files changed on disk.
    static func conflictText(_ conflict: SongConflict) -> String {
        switch conflict {
        case .sourceChanged:
            "The song was changed in another app since you opened it. Nothing was saved."
        case .deleted:
            "The song's file was deleted or renamed in another app. Nothing was saved."
        case .metadataChanged:
            "The song's metadata file was changed in another app and can't be merged. "
                + "Nothing was saved."
        }
    }

    private static func describe(_ error: SetlistError) -> String {
        switch error {
        case .notLoaded:
            "Setlists are not loaded."
        case .setlistNotFound:
            "That setlist no longer exists."
        case let .readOnly(_, reason):
            readOnlyText(reason)
        case .invalidOffsets:
            "Those setlist entries have changed. Try again."
        case .duplicateSong:
            "That song is already in the setlist. A song can be in a setlist only once."
        }
    }

    private static func describe(_ error: ShowError) -> String {
        switch error {
        case let .writeFailed(message):
            "The show file could not be written (\(message))."
        case .claimedElsewhere:
            "This show is open in another Segue window. End it there first."
        case .finished:
            "This show has already ended."
        case .readOnly:
            "This show was saved by a newer version of Segue."
        case .emptySetlist:
            "The setlist has no songs to perform."
        case .songNotFound:
            "That song is no longer in the library."
        case .invalidOffsets, .itemNotFound, .requestNotFound:
            "The set changed meanwhile. Try again."
        case .invalidRating, .notFinished, .notLoaded, .showNotFound:
            "The show could not be updated (\(String(describing: error)))."
        case let .repeatRefused(_, refusal):
            repeatText(refusal)
        }
    }

    /// Why a song cannot be added again in this show (R102).
    static func repeatText(_ refusal: RepeatRefusal) -> String {
        switch refusal {
        case .alreadyPlayed:
            "Already played in this show."
        case .playingNow:
            "That song is playing now."
        case .upcoming:
            "Already in the set."
        case .requested:
            "Already in the requests."
        }
    }

    /// Why an item cannot be edited.
    static func readOnlyText(_ reason: ReadOnlyReason) -> String {
        switch reason {
        case .newerSchema:
            "Created by a newer Segue - update to edit."
        case let .unreadableSidecar(message):
            "Its metadata file could not be read (\(message)), so editing is blocked."
        case let .notUTF8(encoding):
            "This file is not UTF-8 text. It is shown as \(encoding), which may not be "
                + "right, so editing is blocked. Convert it to UTF-8 to edit it."
        }
    }
}
