import Editing
import Foundation
import Library
import MusicTheory
import Services

/// Picking a walk-up in the editor (P8-4b section 8.9): picks live in the song's sidecar,
/// never the `.cho`; every pick and reset is one undo step.
extension SongEditorViewModel {
    /// Picks need the sidecar, which a new song has only after its first save.
    var canPickWalkUps: Bool {
        if case .edit = mode {
            return persistBassPrefs != nil
        }
        return false
    }

    /// The change `id` names in the preview as rendered now, with its section and feel.
    func walkUpDetails(_ id: ChangeID) -> WalkUpDetails? {
        guard let renderModel else { return nil }
        let changes = BassLine.changes(renderModel, document: snapshot.document, prefs: bassPrefs)
        guard let change = changes.first(where: { $0.id == id }) else { return nil }
        let section = renderModel.sections.indices.contains(change.section)
            ? SectionNotes.label(of: renderModel.sections[change.section]) : nil
        return WalkUpDetails(change: change, section: section, feel: songFeel.title)
    }

    /// Saves `candidate` (nil: "Nothing here") as the pick for `change`.
    func pickWalkUp(_ change: ChordChange, _ candidate: WalkUpCandidate?) {
        guard canPickWalkUps, let renderModel,
              let anchor = ChordAnchors.anchor(
                  at: change.id.from,
                  units: SongSections.units(of: snapshot.document),
                  sections: renderModel.sections,
              )
        else { return }
        let pick = WalkUpPick(
            anchor: anchor,
            to: change.toBass,
            kind: candidate?.kind ?? .hold,
            offsets: candidate?.offsets ?? [],
        )
        setBassPrefs(bassPrefs.saving(pick), actionName: "Choose Walk-up")
        services.record(.featureUsed(.walkUpPick, .editor))
        services.record(.walkUpPicked(.choosing(candidate, on: change, feel: songFeel)))
    }

    /// The song's feel, else the profile's default (Pop).
    var songFeel: BassGenre {
        bassPrefs.genre ?? instrument?.profile.genre ?? .pop
    }

    /// Removes the pick on `change`: the chart shows the suggestion again.
    func resetWalkUp(_ change: ChordChange) {
        guard canPickWalkUps, let pick = change.pick else { return }
        setBassPrefs(
            bassPrefs.removing(anchor: pick.anchor, to: pick.to),
            actionName: "Reset Walk-up",
        )
        services.record(.walkUpPicked(.resetting(change, feel: songFeel)))
    }

    /// Replaces the bass prefs, registers the inverse on the editor's undo stack, redraws
    /// the preview and writes the sidecar.
    func setBassPrefs(_ new: BassPrefs, actionName: String) {
        let old = bassPrefs
        guard new != old else { return }
        bassPrefs = new
        #if os(macOS)
            let manager = sourceEditor.undoManager
            manager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.setBassPrefs(old, actionName: actionName) }
            }
            manager.setActionName(actionName)
        #endif
        scheduleRender(delay: .zero)
        guard case let .edit(id) = mode, let persistBassPrefs else { return }
        let previous = bassTask
        bassTask = Task { @MainActor [weak self] in
            await previous?.value
            do {
                _ = try await persistBassPrefs(id, new)
            } catch {
                self?.errorMessage = UserMessage.describe(error)
            }
        }
    }

    /// The song's saved bass prefs and their writer, handed over by the library.
    func attachBassPrefs(
        _ prefs: BassPrefs,
        persist: @escaping (SongID, BassPrefs) async throws -> SongRecord,
    ) {
        bassPrefs = prefs
        persistBassPrefs = persist
        scheduleRender(delay: .zero)
    }

    /// The preview's picking actions (nil outside the bass-note view).
    var walkUpPicking: WalkUpPicking {
        WalkUpPicking(
            isEnabled: canPickWalkUps,
            details: { [weak self] id in self?.walkUpDetails(id) },
            choose: { [weak self] change, candidate in self?.pickWalkUp(change, candidate) },
            reset: { [weak self] change in self?.resetWalkUp(change) },
        )
    }
}
