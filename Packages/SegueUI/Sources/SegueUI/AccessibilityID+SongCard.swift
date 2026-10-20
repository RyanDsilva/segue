// P3-10: accessibility identifiers of the song card, the slash menu and the editor's
// one-click diagnostic fixes. Mirror new IDs in the UITests target (it cannot import
// SegueUI).

public extension AccessibilityID {
    /// "Fix: Change to Bm" under a problem in the editor's problems menu.
    static let editorProblemFix = "segue.editor.status.problemFix"

    /// The `{` list's header ("Directive").
    static let editorCompletionsHeader = "segue.editor.completions.header"

    // MARK: Slash menu

    /// The slash menu's panel.
    static let slashMenu = "segue.editor.slashMenu"
    /// One slash menu row (label = its plain name, value = the directive it writes).
    static let slashMenuItem = "segue.editor.slashMenu.item"
    /// The menu's header: "Insert", or "/cho" while filtering a selection to wrap.
    static let slashMenuFilter = "segue.editor.slashMenu.filter"
}
