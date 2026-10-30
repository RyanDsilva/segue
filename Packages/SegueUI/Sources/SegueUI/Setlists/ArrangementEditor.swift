import Foundation
import Library
import Services

/// The open Arrange Sections sheet's state (P8-3 decisions 4 and 6): the selected chip, the
/// newest arrangement while saves are in flight, and the save queue. Each edit applies to the
/// newest draft and its save is awaited after the one before, so rapid edits are never lost
/// and land as ordered undo steps (R16, R154). The model's arrangement is read again only
/// when no save is pending (an external change, undo, redo).
@MainActor
@Observable
final class ArrangementEditor {
    /// Saves an arrangement (nil = the full song) under an undo name.
    typealias Save = @MainActor (SlotArrangement?, String) async -> Void

    let slot: ArrangingSlot
    /// The selected chip (the keyboard cursor): index-based, clamped to the lane.
    private(set) var selection = 0
    /// A valid roadmap being typed: the lane and the preview show it; nothing is saved until
    /// it is committed.
    var roadmapPreview: [ArrangementPass]?
    /// The newest arrangement while saves are in flight (`.some(nil)` = Reset to Full Song).
    private var pending: SlotArrangement??
    private var inFlight = 0
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private let save: Save
    @ObservationIgnored private let services: ServicesHub

    init(slot: ArrangingSlot, services: ServicesHub, save: @escaping Save) {
        self.slot = slot
        self.services = services
        self.save = save
    }

    /// The sheet's editor, saving through the builder's view model.
    convenience init(slot: ArrangingSlot, model: SetlistsViewModel) {
        self.init(slot: slot, services: model.services) { [weak model] arrangement, name in
            await model?.setArrangement(
                arrangement,
                of: slot.item,
                in: slot.setlist,
                actionName: name,
            )
        }
    }

    /// Whether a save is queued or running.
    var isSaving: Bool {
        inFlight > 0
    }

    /// The slot's arrangement as the sheet shows it: the newest pending one, else `saved`.
    func arrangement(saved: SlotArrangement?) -> SlotArrangement? {
        pending ?? saved
    }

    /// The lane for `saved` (the model's arrangement) and the song's parts, with a roadmap
    /// being typed shown in place of the saved passes.
    func draft(saved: SlotArrangement?, units: [SongSectionUnit]) -> ArrangementDraft {
        let draft = ArrangementDraft(arrangement: arrangement(saved: saved), units: units)
        return roadmapPreview.map(draft.with(passes:)) ?? draft
    }

    func select(_ index: Int, count: Int) {
        selection = Self.clamp(index, count: count)
    }

    /// Keeps the selection in the lane after it shrank (undo, removal).
    func clampSelection(count: Int) {
        let clamped = Self.clamp(selection, count: count)
        if clamped != selection {
            selection = clamped
        }
    }

    /// Applies `edit` to `draft` (the newest one) and queues its save. Returns the refusal,
    /// if any (nothing is saved then).
    @discardableResult
    func perform(_ edit: ArrangementDraft.Edit, on draft: ArrangementDraft)
        -> ArrangementDraft.Refusal?
    {
        switch draft.apply(edit, selection: selection) {
        case let .failure(refusal):
            return refusal
        case let .success(result):
            selection = result.selection
            enqueue(result.arrangement, actionName: result.actionName)
            switch edit {
            case .setMode, .toggleSkip:
                services.record(.featureUsed(.arrangementMode, .builder))
            case .replace:
                services.record(.featureUsed(.arrangementRoadmap, .builder))
            default:
                break
            }
            return nil
        }
    }

    /// Reset to Full Song: removes the arrangement (one undo step).
    func reset() {
        enqueue(nil, actionName: "Reset to Full Song")
    }

    /// Waits until every queued save has landed.
    func settle() async {
        while let queue {
            await queue.value
            if self.queue == queue {
                break
            }
        }
    }

    private func enqueue(_ arrangement: SlotArrangement?, actionName: String) {
        pending = .some(arrangement)
        inFlight += 1
        let previous = queue
        let save = save
        queue = Task { @MainActor [weak self] in
            await previous?.value
            await save(arrangement, actionName)
            guard let self else { return }
            inFlight -= 1
            if inFlight == 0 {
                pending = nil
            }
        }
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        min(max(index, 0), max(count - 1, 0))
    }
}
