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
    /// The "N song files could not be loaded" footer (opens the list of files and reasons).
    public static let libraryLoadIssues = "segue.library.loadIssues"
    /// The spinner shown while a search is in flight and nothing matched yet.
    public static let librarySearching = "segue.library.searching"

    // MARK: Song detail + editor

    public static let songTitle = "segue.song.title"
    public static let editSong = "segue.song.edit"
    public static let editorText = "segue.editor.text"
    /// "Done": closes the editor after a last save.
    public static let editorDone = "segue.editor.done"
    /// The save status ("Saved", "Saving…", "Not saved", "All changes saved").
    public static let editorSaveStatus = "segue.editor.saveStatus"
    /// The inline bar shown when an autosave hit a change made in another app.
    public static let editorConflictBar = "segue.editor.conflict"
    public static let editorConflictReload = "segue.editor.conflict.reload"
    public static let editorConflictOverwrite = "segue.editor.conflict.overwrite"
    public static let editorConflictCopy = "segue.editor.conflict.copy"
    /// The 1.5 s confirmation in the bottom bar ("All changes saved", "Added … to …").
    public static let transientMessage = "segue.main.transient"
    public static let editorPreview = "segue.editor.preview"
    public static let editorError = "segue.editor.error"

    // MARK: Editor (phase 1, unit D)

    public static let editorModeText = "segue.editor.mode.text"
    public static let editorModeVisual = "segue.editor.mode.visual"
    /// The visual canvas text view (lyrics and section labels).
    public static let editorVisual = "segue.editor.visual"
    /// The chord-pill layer over the visual canvas.
    public static let editorVisualChords = "segue.editor.visual.chords"
    /// One chord pill (label = displayed chord).
    public static let editorPill = "segue.editor.pill"
    /// The chord slot above one lyric word (label = the word).
    public static let editorLane = "segue.editor.lane"
    public static let editorChordPopover = "segue.editor.chordPopover"
    public static let editorChordField = "segue.editor.chordPopover.field"
    public static let editorChordSuggestion = "segue.editor.chordPopover.suggestion"
    public static let editorChordDelete = "segue.editor.chordPopover.delete"
    /// The `[` / `{` completion panel and its chips.
    public static let editorCompletions = "segue.editor.completions"
    public static let editorCompletion = "segue.editor.completion"
    public static let editorTransposeDown = "segue.editor.transpose.down"
    public static let editorTransposeUp = "segue.editor.transpose.up"
    public static let editorTransposeValue = "segue.editor.transpose.value"
    public static let editorCapoDown = "segue.editor.capo.down"
    public static let editorCapoUp = "segue.editor.capo.up"
    public static let editorCapoValue = "segue.editor.capo.value"
    public static let editorShapes = "segue.editor.display.shapes"
    public static let editorConcert = "segue.editor.display.concert"
    public static let editorNashville = "segue.editor.display.nashville"
    public static let editorDiagramsToggle = "segue.editor.diagrams"
    public static let editorInstrument = "segue.editor.instrument"
    public static let editorStageColumns = "segue.editor.stageColumns"
    public static let editorTuning = "segue.editor.tuning"
    public static let editorApplyTransposition = "segue.editor.applyTransposition"
    public static let editorFlaggedDefines = "segue.editor.flaggedDefines"
    public static let editorPalette = "segue.editor.palette"
    public static let editorPaletteChord = "segue.editor.palette.chord"
    public static let editorAddChord = "segue.editor.palette.add"
    public static let editorProblems = "segue.editor.status.problems"
    public static let editorCursor = "segue.editor.status.cursor"
    public static let editorFileName = "segue.editor.status.file"
    /// Hidden: keystroke latency stats ("n=40 max=3.1ms mean=1.2ms"), read by E2E.
    public static let editorKeystrokeStats = "segue.editor.status.keystrokes"
    /// Hidden: both editor views' text-input settings ("spelling=off quotes=off ...").
    public static let editorInputSettings = "segue.editor.status.inputSettings"
    public static let editorEditInTextMode = "segue.editor.editInTextMode"
    public static let sheetKey = "segue.sheet.key"

    // MARK: Song sheet (rendered song, preview and stage)

    public static let sheetChord = "segue.sheet.chord"
    public static let sheetLyric = "segue.sheet.lyric"
    public static let sheetSectionLabel = "segue.sheet.sectionLabel"

    // MARK: Chord diagrams (phase 1, unit B)

    public static let diagramStrip = "segue.diagrams.strip"
    public static let guitarDiagram = "segue.diagrams.guitar"
    public static let pianoDiagram = "segue.diagrams.piano"
    public static let shapeEditor = "segue.diagrams.shapeEditor"
    public static let shapeEditorSave = "segue.diagrams.shapeEditor.save"

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
