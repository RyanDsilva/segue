import Foundation
import Library
import Observation
import Services
import Shows
import Support

/// The gig log as the main window sees it: finished gig shows, newest first, and the edits
/// a gig allows afterwards (venue, date, notes, rating; delete).
@MainActor
@Observable
public final class GigLogViewModel {
    public private(set) var entries: [GigLogEntry] = []
    public var selection: ShowID?
    /// The gig to select once the log first loads (restored from the last launch).
    var restoredSelection: ShowID?
    /// The last failure, shown as a dismissible banner.
    public var errorMessage: String?

    private let shows: ShowStore
    /// The main window's undo manager (Edit > Undo).
    @ObservationIgnored weak var undoManager: UndoManager?
    /// Records analytics events (WS3 spec 5); the session hands over the app's hub.
    @ObservationIgnored public var services: ServicesHub = .disabled
    /// Undo targets of Move Gig to Trash, one per gig.
    let trashTargets = UndoTargets<ShowID>()
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
        if let restored = restoredSelection {
            restoredSelection = nil
            if entries.contains(where: { $0.id == restored }) {
                selection = restored
            }
        }
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
            services.record(.featureUsed(.gigLogEdit, .library))
        } catch {
            errorMessage = UserMessage.describe(error)
        }
        await reload()
    }

    /// Moves a gig's show file to the Trash (its songs no longer count as played); Edit >
    /// Undo puts it back with its plays.
    public func delete(_ id: ShowID) async {
        let pending = Task { await trash(id) }
        guard await pending.value != nil else { return }
        TrashUndo(
            manager: undoManager,
            target: trashTargets.target(for: id),
            actionName: "Move Gig to Trash",
            trash: { [weak self] in await self?.trash(id) },
            restore: { [weak self] receipt in await self?.restore(receipt) ?? false },
        ).register(pending: pending)
    }

    /// The show file of gig `id`, for Show in Finder.
    public func fileURL(for id: ShowID) async -> URL? {
        await shows.fileURL(for: id)
    }

    private func trash(_ id: ShowID) async -> TrashReceipt? {
        do {
            let receipt = try await shows.delete(id)
            if selection == id {
                selection = nil
            }
            await reload()
            await onPlaysChanged()
            return receipt
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return nil
        }
    }

    private func restore(_ receipt: TrashReceipt) async -> Bool {
        do {
            let restored = try await shows.restore(receipt)
            await reload()
            await onPlaysChanged()
            guard let restored else {
                errorMessage = "Could not undo Move Gig to Trash: the file could not be read."
                return false
            }
            selection = restored.id
            return true
        } catch {
            errorMessage = "Could not undo Move Gig to Trash. " + UserMessage.describe(error)
            return false
        }
    }
}
