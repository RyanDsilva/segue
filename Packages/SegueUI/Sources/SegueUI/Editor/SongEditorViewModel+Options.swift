import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
#if os(macOS)
    import AppKit
#endif

public extension SongEditorViewModel {
    // MARK: Display options

    /// Steps the view transposition by `delta`, wrapping within -11 ... +11.
    func stepTranspose(by delta: Int) {
        var value = options.transpose + delta
        if value > 11 {
            value -= 12
        } else if value < -11 {
            value += 12
        }
        updateOptions { $0.transpose = value }
    }

    func setCapoMode(_ mode: CapoMode) {
        updateOptions { $0.capoMode = mode }
    }

    func setNashville(_ on: Bool) {
        updateOptions { $0.nashville = on }
    }

    func setShowDiagrams(_ on: Bool) {
        updateOptions { $0.showDiagrams = on }
    }

    func setInstrument(_ instrument: Instrument) {
        updateOptions { $0.instrument = instrument }
    }

    /// Sets the song's tuning in both places (open question 5): the sidecar, and
    /// `{meta: tuning}` in the source (removed again for standard tuning).
    func setTuning(_ tuning: Tuning) {
        updateOptions { $0.tuning = tuning }
        let current = snapshot.document.metadata.extra["tuning"]?.first
        if tuning == .standard {
            if current != nil {
                perform(.setMeta(name: "tuning", value: nil))
            }
        } else if current.flatMap(Tuning.init(metaValue:)) != tuning {
            perform(.setMeta(name: "tuning", value: tuning.metaValue))
        }
    }

    /// Changes `{capo}` in the source (an undoable edit; 0 removes it).
    func stepCapo(by delta: Int) {
        let value = min(max(capo + delta, 0), 11)
        guard value != capo else { return }
        perform(.setDirective(name: "capo", value: value == 0 ? nil : String(value)))
    }

    /// The song's column count on stage: nil = the Settings > Live default (or auto-fit),
    /// else 1...3 (decisions.md, "Columns": the song's choice wins). Saved to the sidecar's
    /// live memory, the same value the stage's C key cycles.
    func setStageColumns(_ columns: Int?) {
        var prefs = livePrefs
        prefs.columns = columns
        guard prefs != livePrefs else { return }
        livePrefs = prefs
        guard case let .edit(id) = mode, let persistLivePrefs, prefs != savedLivePrefs else {
            return
        }
        savedLivePrefs = prefs
        let previous = prefsTask
        prefsTask = Task { [weak self] in
            await previous?.value
            do {
                _ = try await persistLivePrefs(id, prefs)
            } catch {
                self?.errorMessage = UserMessage.describe(error)
            }
        }
    }

    internal func updateOptions(_ change: (inout DisplayOptions) -> Void) {
        var updated = options
        change(&updated)
        guard updated != options else { return }
        options = updated
        refreshCanvas()
        scheduleRender(delay: .zero)
        persistOptions()
    }

    /// Writes the toggles to the sidecar (edits only; a new song writes them on save).
    internal func persistOptions() {
        guard case let .edit(id) = mode, let persistPrefs else { return }
        let prefs = DisplayPrefs(options)
        guard prefs != savedPrefs else { return }
        savedPrefs = prefs
        let previous = prefsTask
        prefsTask = Task { [weak self] in
            await previous?.value
            do {
                _ = try await persistPrefs(id, prefs)
            } catch {
                self?.errorMessage = UserMessage.describe(error)
            }
        }
    }
}
