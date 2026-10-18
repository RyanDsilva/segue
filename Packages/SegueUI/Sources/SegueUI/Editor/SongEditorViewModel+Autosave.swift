import Foundation
import Library

/// Autosave (WS2a 3.4, R17): the editor's text reaches disk on its own; the window shows
/// "Saved", "Saving…" or "Not saved", and an edited dot while a change waits to be saved.
public extension SongEditorViewModel {
    /// What the subtitle says about the file.
    enum SaveState: Equatable, Sendable {
        /// A new song with nothing written yet.
        case new
        /// Everything typed is on disk (a change waiting for the debounce still reads as
        /// saved; the window's edited dot shows it).
        case saved
        /// "All changes saved" after File > Save, for 1.5 s.
        case confirmed
        case saving
        /// The last save failed, or a conflict paused autosave.
        case notSaved

        /// The subtitle text.
        public var text: String {
            switch self {
            case .new: "New song"
            case .saved: "Saved"
            case .confirmed: "All changes saved"
            case .saving: "Saving…"
            case .notSaved: "Not saved"
            }
        }
    }

    var saveState: SaveState {
        if conflict != nil || lastSaveFailed {
            return .notSaved
        }
        if isSaving {
            return .saving
        }
        if case .create = mode {
            return .new
        }
        return isConfirmingSave ? .confirmed : .saved
    }

    /// Whether closing the editor now would need a save first (pending, in flight, failed
    /// or in conflict).
    var needsFlush: Bool {
        hasUnsavedChanges || isSaving || conflict != nil || autosave.isPending
    }

    /// Saves now. Returns whether every edit is on disk; false while a conflict is
    /// unresolved or when the save failed (the subtitle then says "Not saved").
    @discardableResult
    func flush() async -> Bool {
        guard conflict == nil else { return false }
        if hasUnsavedChanges, !autosave.isPending {
            // A change that never reached the scheduler (e.g. a failed save's text).
            autosave.noteChange()
        }
        let saved = await autosave.flush()
        return saved && !hasUnsavedChanges && conflict == nil
    }

    /// File > Save in the editor: saves now, then shows "All changes saved" for 1.5 s.
    func confirmSave() async {
        guard await flush() else { return }
        isConfirmingSave = true
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.isConfirmingSave = false
        }
    }

    /// Forgets unsaved edits (the user chose Discard Edits, or the editor closes after its
    /// edits went elsewhere): stops autosave and releases the sudden-termination hold.
    func discardPending() {
        autosave.discard()
        confirmationTask?.cancel()
        SuddenTermination.hold(self, false)
    }

    /// The file changed on disk while nothing here was unsaved: show the new text as one
    /// undoable step ("Reload from Disk"), and treat it as saved.
    func reloadFromDisk(_ record: SongRecord) {
        guard !hasUnsavedChanges, !isSaving, record.source != source else {
            originalSource = record.source
            return
        }
        originalSource = record.source
        #if os(macOS)
            if let sourceController {
                sourceController.replaceAll(with: record.source, actionName: "Reload from Disk")
                updateDirty()
                return
            }
        #endif
        sourceTextDidChange(record.source)
    }

    /// The conflict was settled (overwritten, reloaded): saves resume, `record` is on disk.
    func conflictResolved(saved record: SongRecord?) {
        conflict = nil
        lastSaveFailed = false
        errorMessage = nil
        if let record {
            originalSource = record.source
            fileName = record.relativePath
        }
        updateDirty()
        autosave.resume()
        if !hasUnsavedChanges {
            autosave.discard()
        }
    }

    /// Recomputes `hasUnsavedChanges` after a change and tells autosave about it.
    internal func updateDirty() {
        let dirty = switch mode {
        case .create:
            !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .edit:
            source != originalSource
        }
        if dirty != hasUnsavedChanges {
            hasUnsavedChanges = dirty
        }
        if dirty {
            autosave.noteChange()
        }
    }

    /// The autosave step: nothing to do counts as saved.
    internal func saveNow() async -> Bool {
        guard hasUnsavedChanges else { return true }
        return await commit() != nil
    }

    internal func noteSaveFailure(_ error: any Error) {
        switch error {
        case let LibraryError.conflict(_, kind):
            conflict = kind
            autosave.pause()
        case LibraryError.songNotFound:
            conflict = .deleted
            autosave.pause()
        default:
            lastSaveFailed = true
            errorMessage = UserMessage.describe(error)
        }
    }
}

/// Keeps macOS from terminating the app suddenly while any editor holds unsaved edits
/// (`ProcessInfo.disableSuddenTermination`, balanced per holder).
@MainActor
enum SuddenTermination {
    private static var holders: Set<ObjectIdentifier> = []

    static func hold(_ holder: AnyObject, _ held: Bool) {
        let id = ObjectIdentifier(holder)
        if held, holders.insert(id).inserted {
            ProcessInfo.processInfo.disableSuddenTermination()
        } else if !held, holders.remove(id) != nil {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
    }
}
