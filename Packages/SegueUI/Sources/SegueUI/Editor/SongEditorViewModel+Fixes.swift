import Editing

extension SongEditorViewModel {
    /// Applies a diagnostic's one-click fix (R81, e.g. `{key: Hm}` -> `{key: Bm}`) as one
    /// undoable edit. The fix is re-derived from the current snapshot, since the listed
    /// diagnostics can trail the text by one render; a fix that no longer applies is a
    /// no-op.
    func applyFix(of diagnostic: EditorDiagnostic) {
        guard let title = diagnostic.fix?.title,
              let current = snapshot.diagnostics.first(where: {
                  $0.line == diagnostic.line && $0.fix?.title == title
              }),
              let fix = current.fix
        else { return }
        apply(fix.change)
    }
}
