// P3-4: accessibility identifiers of the paste review sheet and its entry points. Mirror
// new IDs in the UITests target (it cannot import SegueUI).

public extension AccessibilityID {
    /// The review sheet (input state, one song or a batch).
    static let pasteSheet = "segue.paste.sheet"
    /// The input state's text area ("Paste or type a song").
    static let pasteInput = "segue.paste.input"
    /// The input state's "Continue".
    static let pasteContinue = "segue.paste.continue"
    /// The input state's "Start blank".
    static let pasteStartBlank = "segue.paste.startBlank"
    /// The original text (left side).
    static let pasteOriginal = "segue.paste.original"
    /// The result preview (right side).
    static let pasteResult = "segue.paste.result"
    /// The result's ChordPro text (Edit in Text).
    static let pasteResultText = "segue.paste.resultText"
    /// A section label in the result preview (label = its name, value "AI" when a model
    /// decided it).
    static let pasteSectionLabel = "segue.paste.sectionLabel"
    /// Swap Title and Artist.
    static let pasteSwap = "segue.paste.swap"
    /// Edit in Text / Preview.
    static let pasteEditToggle = "segue.paste.editToggle"
    /// "Refining with ..." while a model runs.
    static let pasteRefining = "segue.paste.refining"
    /// The footer's provider line.
    static let pasteProvider = "segue.paste.provider"
    /// The footer's quiet link to Settings > AI (R93).
    static let pasteDownloadLink = "segue.paste.downloadLink"
    /// The footer's R69 "Open System Settings".
    static let pasteOpenSystemSettings = "segue.paste.openSystemSettings"
    /// Accept / Import N Songs.
    static let pasteAccept = "segue.paste.accept"
    static let pasteCancel = "segue.paste.cancel"
    /// "Looks like ... in your library" / "Already in your library as ..." beside the card.
    static let pasteNearDuplicate = "segue.paste.nearDuplicate"
    /// The line under the draft's artists for a split the converter made, and its Keep as
    /// one button (P8-8 section 3.7).
    static let pasteArtistSplit = "segue.paste.artistSplit"
    static let pasteKeepAsOne = "segue.paste.keepAsOne"
    /// One batch file row (label = file name).
    static let pasteBatchRow = "segue.paste.batchRow"
    /// A batch file's checkbox (label = file name).
    static let pasteBatchTick = "segue.paste.batchTick"
    /// The empty library's "Paste a Song".
    static let pasteFromEmptyLibrary = "segue.library.pasteSong"
}
