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

    /// The input state's hint line (Paste the Page Instead's copy-the-page hint).
    static let pasteHint = "segue.paste.hint"

    // P9-4 spec 14 (Personal build only): the web field, Find Lyrics and Open Here.
    static let pasteWebField = "segue.paste.webField"
    static let pasteWebImport = "segue.paste.webImport"
    static let pasteWebMessage = "segue.paste.webMessage"
    static let pasteWebHelp = "segue.paste.webHelp"
    /// A failure's action (Open in Safari, Import a Saved Page..., ...), by its title.
    static let pasteWebAction = "segue.paste.webAction"
    static let findLyricsSheet = "segue.findLyrics.sheet"
    static let findLyricsField = "segue.findLyrics.field"
    static let findLyricsArtist = "segue.findLyrics.artist"
    static let findLyricsResults = "segue.findLyrics.results"
    /// A group heading; the group's technique name follows.
    static func findLyricsGroup(_ group: String) -> String {
        "segue.findLyrics.group.\(group)"
    }

    /// A group's status line and its actions.
    static let findLyricsStatus = "segue.findLyrics.status"
    /// A song row, by its position in the whole list.
    static func findLyricsResult(_ index: Int) -> String {
        "segue.findLyrics.result.\(index)"
    }

    /// A version row under a song, by its position in the whole list.
    static func findLyricsVersion(_ index: Int) -> String {
        "segue.findLyrics.version.\(index)"
    }

    static let findLyricsPreview = "segue.findLyrics.preview"
    static let findLyricsReview = "segue.findLyrics.review"
    static let findLyricsAttribution = "segue.findLyrics.attribution"
    static let findLyricsHelp = "segue.findLyrics.help"
    static let reviewSourceLine = "segue.paste.sourceLine"
    static let emptyLibraryWebImport = "segue.library.webImport"
    static let emptyLibraryFindLyrics = "segue.library.findLyrics"
    static let webOpenHere = "segue.web.openHere"
    static let openHereSheet = "segue.web.openHereSheet"
    static let clearSiteData = "segue.settings.clearSiteData"
}
