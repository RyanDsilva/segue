import Foundation
import Library
import Observation
import Shows

/// The gig log as the main window sees it: finished gig shows, newest first, and the edits
/// a gig allows afterwards (venue, date, notes, rating; delete).
@MainActor
@Observable
public final class GigLogViewModel {
    public private(set) var entries: [GigLogEntry] = []
    public var selection: ShowID?
    /// The last failure, shown as a dismissible banner.
    public var errorMessage: String?

    private let shows: ShowStore
    /// The autosave timing gig details use (the same policy as the song editor, B-13).
    let autosave: AutosaveTiming
    /// Called after a change that alters play history (delete), so "last played" and
    /// "times played" refresh.
    private let onPlaysChanged: @MainActor () async -> Void

    public init(
        shows: ShowStore,
        autosave: AutosaveTiming = .standard,
        onPlaysChanged: @escaping @MainActor () async -> Void,
    ) {
        self.shows = shows
        self.autosave = autosave
        self.onPlaysChanged = onPlaysChanged
    }

    /// The selected entry, if any.
    public var selected: GigLogEntry? {
        guard let selection else { return nil }
        return entries.first { $0.id == selection }
    }

    public func reload() async {
        entries = await shows.gigLog()
        if let selection, !entries.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        if selection == nil {
            selection = entries.first?.id
        }
    }

    /// Saves a gig's venue, date, notes and rating.
    public func update(_ details: GigDetails, of id: ShowID) async {
        guard entries.first(where: { $0.id == id })?.details != details else { return }
        do {
            try await shows.updateGigDetails(details, of: id)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    /// Deletes a gig (its show file and its plays).
    public func delete(_ id: ShowID) async {
        do {
            try await shows.delete(id)
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
        await onPlaysChanged()
    }
}
