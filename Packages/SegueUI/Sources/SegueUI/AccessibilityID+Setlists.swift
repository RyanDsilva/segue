// Phase 2: accessibility identifiers of the setlist builder, library metadata, gig log and
// reorder review. Owner: unit D. Mirror new IDs in the UITests target (it cannot import
// SegueUI).

import Library

public extension AccessibilityID {
    // MARK: Sidebar

    static let sidebarGigLog = "segue.sidebar.gigLog"
    /// A tag row under "Tags" (filters the library by it).
    static let sidebarTag = "segue.sidebar.tag"

    // MARK: Filter chips (library and builder)

    static let filterChips = "segue.filter.chips"
    static let filterTag = "segue.filter.tag"
    static func filterProficiency(_ level: Proficiency) -> String {
        "segue.filter.proficiency.\(level.rawValue)"
    }

    // MARK: Song metadata (library detail)

    static let songMeta = "segue.song.meta"
    static let songPlayStats = "segue.song.playStats"
    static func songProficiency(_ level: Proficiency) -> String {
        "segue.song.proficiency.\(level.rawValue)"
    }

    static let songTag = "segue.song.tag"
    static let songTagRemove = "segue.song.tag.remove"
    static let songTagField = "segue.song.tag.field"
    static let songNotes = "segue.song.notes"
    static let songCue = "segue.song.cue"
    static let songEditNotes = "segue.song.editNotes"
    static let notesEditorText = "segue.notesEditor.text"
    static let notesEditorAddCue = "segue.notesEditor.addCue"
    static let notesEditorCueSection = "segue.notesEditor.cue.section"
    static let notesEditorCueText = "segue.notesEditor.cue.text"
    static let notesEditorCueRemove = "segue.notesEditor.cue.remove"
    static let notesEditorSave = "segue.notesEditor.save"

    // MARK: Setlist builder

    static let builderLibrary = "segue.builder.library"
    static let builderSearch = "segue.builder.search"
    static let builderLibraryRow = "segue.builder.library.row"
    static let builderAdd = "segue.builder.add"
    static let setlistTotal = "segue.setlist.total"
    static let setlistTarget = "segue.setlist.target"
    static let setlistDetailsLine = "segue.setlist.detailsLine"
    static let setlistStartShow = "segue.setlist.startShow"
    static let setlistRehearse = "segue.setlist.rehearse"
    static let setlistMenu = "segue.setlist.menu"
    static let setlistDropZone = "segue.setlist.dropZone"
    static let entryTitle = "segue.setlist.entry.title"
    static let entryKey = "segue.setlist.entry.key"
    static let entryCapo = "segue.setlist.entry.capo"
    static let entryLength = "segue.setlist.entry.length"
    static let entryStart = "segue.setlist.entry.start"
    static let entryNote = "segue.setlist.entry.note"
    static let entryEdit = "segue.setlist.entry.edit"
    static let entryRemove = "segue.setlist.entry.remove"
    static let entryTransposeDown = "segue.entryEditor.transpose.down"
    static let entryTransposeUp = "segue.entryEditor.transpose.up"
    static let entryTransposeValue = "segue.entryEditor.transpose.value"
    static let entryCapoDown = "segue.entryEditor.capo.down"
    static let entryCapoUp = "segue.entryEditor.capo.up"
    static let entryCapoValue = "segue.entryEditor.capo.value"
    static let entryNoteField = "segue.entryEditor.note"
    static let entryReset = "segue.entryEditor.reset"
    static let entryDone = "segue.entryEditor.done"

    // MARK: Setlist name, details, delete

    static let setlistNameField = "segue.setlistName.field"
    static let setlistNameSave = "segue.setlistName.save"
    static let setlistRenameAction = "segue.setlist.action.rename"
    static let setlistDuplicateAction = "segue.setlist.action.duplicate"
    static let setlistDeleteAction = "segue.setlist.action.delete"
    static let setlistDetailsAction = "segue.setlist.action.details"
    static let detailsVenue = "segue.setlistDetails.venue"
    static let detailsHasDate = "segue.setlistDetails.hasDate"
    static let detailsDate = "segue.setlistDetails.date"
    static let detailsTarget = "segue.setlistDetails.target"
    static let detailsSave = "segue.setlistDetails.save"

    // MARK: Gig log

    static let gigLogList = "segue.gigLog.list"
    static let gigLogRow = "segue.gigLog.row"
    static let gigLogEmpty = "segue.gigLog.empty"
    static let gigTitle = "segue.gig.title"
    static let gigSummary = "segue.gig.summary"
    static let gigVenue = "segue.gig.venue"
    static let gigDate = "segue.gig.date"
    static let gigNotes = "segue.gig.notes"
    static func gigRating(_ value: Int) -> String {
        "segue.gig.rating.\(value)"
    }

    static let gigPlayedRow = "segue.gig.played"
    static let gigSkippedRow = "segue.gig.skipped"
    static let gigDelete = "segue.gig.delete"

    // MARK: Reorder review (show end)

    static let reorderSheet = "segue.reorder"
    static let reorderPlannedRow = "segue.reorder.planned"
    static let reorderPerformedRow = "segue.reorder.performed"
    static let reorderInclude = "segue.reorder.include"
    static let reorderSave = "segue.reorder.save"
    static let reorderDiscard = "segue.reorder.discard"
}
