import Foundation
import Library
import Setlists

/// Turns errors into short, user-facing sentences.
enum UserMessage {
    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as LibraryError:
            describe(error)
        case let error as SetlistError:
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
        }
    }

    /// Why an item cannot be edited.
    static func readOnlyText(_ reason: ReadOnlyReason) -> String {
        switch reason {
        case .newerSchema:
            "Created by a newer Segue - update to edit."
        case let .unreadableSidecar(message):
            "Its metadata file could not be read (\(message)), so editing is blocked."
        }
    }
}
