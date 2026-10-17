import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
#if os(macOS)
    import AppKit
#endif

extension SongEditorViewModel {
    // MARK: Edits

    /// Applies a tree operation as one undoable source edit. Returns false (and beeps) when
    /// the operation does not apply to this snapshot.
    @discardableResult
    func perform(_ operation: EditOperation) -> Bool {
        do {
            let change = try DocumentEditor.change(for: operation, in: snapshot)
            if case let .editLyrics(path, _, _) = operation {
                pendingLyricEdit = path
            }
            defer { pendingLyricEdit = nil }
            apply(change)
            return true
        } catch {
            #if os(macOS)
                NSSound.beep()
            #endif
            return false
        }
    }

    /// "Apply transposition to source": rewrites chords and `{key}` by the current view
    /// transposition (one undo step), keeps `{capo}`, resets the view to +0 and lists the
    /// custom shapes that need review.
    public func applyTranspositionToSource() {
        let semitones = options.transpose
        guard semitones != 0 else { return }
        let plan = TranspositionRewrite.plan(semitones: semitones, in: snapshot)
        apply(plan.change)
        flaggedDefines = plan.flaggedDefines
        updateOptions { $0.transpose = 0 }
    }

    public func dismissFlaggedDefines() {
        flaggedDefines = []
    }

    /// Writes a custom shape into the song as a `{define}`.
    func saveDefine(_ definition: ChordDefinition) {
        perform(.setDefine(definition))
    }

    /// The source chord name a displayed diagram stands for, when the display shows chords
    /// as written (custom shapes are drawn for the written chord). Nil when transposed.
    func sourceChordName(forDiagram diagram: RenderDiagram) -> String? {
        let transform = renderModel?.transform
        let shifted = options.instrument == .piano
            ? (transform?.concertSemitones ?? 0)
            : (transform?.semitones ?? 0)
        guard shifted == 0 else { return nil }
        let name = options.instrument == .piano ? diagram.concertName : diagram.name
        return snapshot.chords.first { $0.token.original == name }?.token.original ?? name
    }

    func apply(_ change: SourceChange) {
        #if os(macOS)
            sourceEditor.apply(change)
        #else
            sourceTextDidChange(source.applying(change.edits))
        #endif
    }
}
