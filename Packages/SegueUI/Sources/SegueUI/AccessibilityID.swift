/// Accessibility identifiers shared by views and XCUITests. The UI test target cannot import
/// SegueUI (it drives the app out of process), so `UITests/` mirrors these strings; keep the
/// two in sync.
public enum AccessibilityID {
    // MARK: Library chooser (first launch)

    /// The "Segue" wordmark on the first-launch library chooser.
    public static let rootTitle = "segue.root.title"
    public static let chooserCreate = "segue.chooser.create"
    public static let chooserOpen = "segue.chooser.open"
    public static let chooserMessage = "segue.chooser.message"

    // MARK: Sidebar

    public static let sidebarLibrary = "segue.sidebar.library"
    public static let sidebarSetlists = "segue.sidebar.setlists"

    // MARK: Library

    public static let songList = "segue.library.list"
    public static let songRow = "segue.library.row"
    public static let newSong = "segue.library.newSong"
    public static let refreshLibrary = "segue.library.refresh"
    public static let librarySearch = "segue.library.search"
    public static let libraryEmpty = "segue.library.empty"

    // MARK: Song detail + editor

    public static let songTitle = "segue.song.title"
    public static let editSong = "segue.song.edit"
    public static let editorText = "segue.editor.text"
    public static let editorSave = "segue.editor.save"
    public static let editorCancel = "segue.editor.cancel"
    public static let editorPreview = "segue.editor.preview"
    public static let editorError = "segue.editor.error"

    // MARK: Song sheet (rendered song, preview and stage)

    public static let sheetChord = "segue.sheet.chord"
    public static let sheetLyric = "segue.sheet.lyric"
    public static let sheetSectionLabel = "segue.sheet.sectionLabel"

    // MARK: Setlists

    public static let setlistList = "segue.setlists.list"
    public static let setlistRow = "segue.setlists.row"
    public static let newSetlist = "segue.setlists.new"
    public static let newSetlistName = "segue.setlists.new.name"
    public static let newSetlistCreate = "segue.setlists.new.create"
    public static let setlistTitle = "segue.setlist.title"
    public static let setlistEntries = "segue.setlist.entries"
    public static let setlistEntry = "segue.setlist.entry"
    public static let setlistAddSongs = "segue.setlist.addSongs"
    public static let setlistPerform = "segue.setlist.perform"
    public static let setlistEmpty = "segue.setlist.empty"
    public static let addSongsSearch = "segue.addSongs.search"
    public static let addSongsRow = "segue.addSongs.row"
    public static let addSongsAdd = "segue.addSongs.add"
    public static let addSongsDone = "segue.addSongs.done"

    // MARK: Acknowledgements

    public static let acknowledgements = "segue.acknowledgements"

    // MARK: Live view

    public static let liveView = "segue.live"
    public static let liveTitle = "segue.live.title"
    public static let liveMeta = "segue.live.meta"
    public static let livePosition = "segue.live.position"
    public static let liveUpNext = "segue.live.upNext"
}
