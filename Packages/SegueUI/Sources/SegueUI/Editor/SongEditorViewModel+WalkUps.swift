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
        let changes = BassLine.changes(
            renderModel,
            document: snapshot.document,
            prefs: bassPrefs,
            parts: parts,
        )
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

    /// The song's saved bass prefs and fills, and the prefs' writer, handed over by the
    /// library.
    func attachBassPrefs(
        _ prefs: BassPrefs,
        parts: [Part] = [],
        persist: @escaping (SongID, BassPrefs) async throws -> SongRecord,
    ) {
        bassPrefs = prefs
        self.parts = parts
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

    /// The Walk-ups list for this song (nil until it is rendered, or outside the bass-note
    /// view); every change is one undo step.
    var walkUpsSource: WalkUpsSource? {
        guard let renderModel, renderModel.transform.options.bass?.notes == true else {
            return nil
        }
        let document = snapshot.document
        let key = renderModel.transform.key.writtenKey
        let sections = renderModel.sections
        let concert = renderModel.transform.concertKey
        return WalkUpsSource(
            title: renderModel.header.title ?? "Untitled",
            changes: BassLine.changes(
                renderModel,
                document: document,
                prefs: bassPrefs,
                parts: parts,
            ),
            sectionLabel: { index in
                sections.indices.contains(index) ? SectionNotes.label(of: sections[index]) : nil
            },
            unmatched: BassLine.unmatched(renderModel, document: document, prefs: bassPrefs)
                .map { ($0, $0.savedSummary(key: key)) },
            feel: bassPrefs.genre,
            defaultFeel: instrument?.profile.genre ?? .pop,
            scale: bassPrefs.mode,
            defaultScale: FillMode.standard(genre: songFeel, key: concert),
            scales: FillMode.choices(for: concert),
            density: instrument?.profile.walkUps ?? .off,
            readOnlyHelp: canPickWalkUps ? nil : "Save the song first",
            picking: walkUpPicking,
            setFeel: { [weak self] genre in self?.setSongFeel(genre) },
            setScale: { [weak self] mode in self?.setSongScale(mode) },
            remove: { [weak self] picks in self?.removeWalkUps(picks) },
        )
    }

    /// The song's own feel (nil: the profile's default), one undo step.
    func setSongFeel(_ genre: BassGenre?) {
        guard canPickWalkUps, genre != bassPrefs.genre else { return }
        var prefs = bassPrefs
        prefs.genre = genre
        setBassPrefs(prefs, actionName: "Change Feel")
        services.record(.featureUsed(.songFeel, .editor))
    }

    /// The song's own scale (nil: the default from its feel and key, R170), one undo step.
    func setSongScale(_ mode: FillMode?) {
        guard canPickWalkUps, mode != bassPrefs.mode else { return }
        var prefs = bassPrefs
        prefs.mode = mode
        setBassPrefs(prefs, actionName: "Change Scale")
        services.record(.featureUsed(.songScale, .editor))
    }

    /// Removes saved picks that no longer match the song, one undo step.
    func removeWalkUps(_ picks: [WalkUpPick]) {
        guard canPickWalkUps, !picks.isEmpty else { return }
        var prefs = bassPrefs
        prefs.walkUps.removeAll { picks.contains($0) }
        setBassPrefs(prefs, actionName: picks.count == 1 ? "Remove Walk-up" : "Remove Walk-ups")
    }
}
