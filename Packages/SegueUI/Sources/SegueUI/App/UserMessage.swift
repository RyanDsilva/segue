import Foundation
import Library
import Services
import Setlists
import Shows

/// Turns errors into short, user-facing sentences.
enum UserMessage {
    /// The library opened but its bookmark could not be stored.
    static func notRemembered(_ url: URL, _ error: any Error) -> String {
        "Segue opened “\(url.lastPathComponent)” but could not remember it "
            + "(\(describe(error))). You will be asked to choose it again next time."
    }

    /// End Show failed but the show was offered again (R154).
    static func unclosedShow(_ error: any Error) -> String {
        "The show could not be closed (\(describe(error))). It is still open: "
            + "Resume it, or try End Show again."
    }

    /// The analytics and report code for `error` shown as a banner (P9-5, R199): a save
    /// refused because the file changed on disk is `saveConflict` wherever it happens, and
    /// an unopened library `libraryOpenFailed`; anything else is the site's `fallback`.
    static func code(for error: any Error, else fallback: ErrorCode) -> ErrorCode {
        switch error as? LibraryError {
        case .conflict: .saveConflict
        case .notOpen: .libraryOpenFailed
        default: fallback
        }
    }

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
        case let .medley(_, refusal):
            medleyText(refusal)
        }
    }

    /// Why a medley edit was refused (P9-3 5.6).
    static func medleyText(_ refusal: MedleyRefusal) -> String {
        switch refusal {
        case .tooFewSongs:
            "A medley needs two or more songs."
        case .tooManyMembers:
            "A medley holds at most \(SetlistMedley.maxMembers) songs."
        case .notASongSlot:
            "Only songs can go in a medley: breaks and medleys stay outside."
        case .notFound:
            "That medley has changed. Try again."
        case let .duplicate(_, occurrence):
            occurrence.isMember
                ? "That song is already \(occurrence.label), in a medley. A song can be in "
                + "one medley only, once."
                : "That song is already \(occurrence.label) in the set, and would be there "
                + "twice."
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
