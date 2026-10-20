// P3-10: accessibility identifiers of the song card, the slash menu and the editor's
// one-click diagnostic fixes. Mirror new IDs in the UITests target (it cannot import
// SegueUI).

public extension AccessibilityID {
    /// "Fix: Change to Bm" under a problem in the editor's problems menu.
    static let editorProblemFix = "segue.editor.status.problemFix"
}
