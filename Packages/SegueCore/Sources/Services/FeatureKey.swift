// WS3 spec 5 row 8: the closed `segue.feature` vocabulary (kept in its own file so
// AnalyticsEvent.swift stays within the file length limit).

/// Row 8 `segue.feature`. Chord palette use is row 18, not a key here.
public enum FeatureKey: String, Sendable, CaseIterable {
    case transpose
    case capo
    case nashville
    case diagrams
    case instrumentPiano
    case tuningChange
    case applyTransposeToSource
    case editorModeSwitch
    case search
    case filterChips
    case setlistEdit
    case setlistTarget
    case autoScroll
    case stageSearch
    case playNow
    case requests
    case columnsCycle
    case stageZoom
    case gigLogEdit
    case liveSettings
    case shapeEditor
    case showInFinder
    case undoInBuilder
    /// P8-8 section 8: a song's artist list changed in the chip field (editor, library), its
    /// Movie / Album set, a combined artist chip split with Split.
    case songArtists
    case songAlbum
    case artistSplit
    /// P8-8 section 8: a tempo written from the set's no-time list, the assistant's left-out
    /// list or Arrange Sections (builder context).
    case tempoFromSet
    /// The stage metronome was switched on (R90, P3-14).
    case metronome
    /// P8-2 (R148, R150): a stage section jump (once per session), the rehearsal loop
    /// switched on.
    case sectionJump
    case sectionLoop
    /// R163: a single-song Rehearse or Live session started from the library, one key per
    /// kind (replacing P8-2's `singleSongSession`).
    case singleSongRehearse
    case singleSongLive
    /// P8-4 6.6: "I play bass" turned on, the bass-note view toggled (editor or stage), the
    /// stage mini neck shown (once per run).
    case bassProfile
    case bassNotes
    case bassNeck
    /// P8-4b 8.12: walk-ups on charts turned on (Settings), a walk-up pick or "Nothing
    /// here" saved, a song's feel set (editor or library); R170: a song's scale set (editor
    /// or library).
    case walkUps
    case walkUpPick
    case songFeel
    case songScale
    /// P8-3 section 9: a pass's show mode set in Arrange Sections (no song data), a roadmap
    /// committed, "Rehearse this" started.
    case arrangementMode
    case arrangementRoadmap
    case arrangementRehearse
    /// P8-6 section 14: a chord heard (editor, library), a walk-up candidate auditioned
    /// (editor, library), play-along started (editor, library, a rehearsal's stage) and its
    /// timing changed, a non-default audio output chosen (never its name), the chord sound
    /// set to clean guitar (Settings).
    case hearChord
    case walkUpAudition
    case playAlong
    case playAlongTiming
    case audioOutput
    case chordSoundGuitar
    /// P8-7 section 15: a Tap Timing capture kept (editor, library), a `{key}`, `{time}` or
    /// `{tempo}` inserted from the editor's menus or the tap review, the key-change chip
    /// confirmed (editor).
    case timingTap
    case chartDirective
    case keyChangeChip
    /// P8-7 section 15: the fill editor opened from a span (editor, library), a candidate or
    /// the draft played in it, its piano roll used (once per sheet).
    case fillEditor
    case fillAudition
    case fillPianoRoll
    /// P8-7 section 15: "Fills as tab" turned on (stage `t`, the editor's Bass menu,
    /// Settings).
    case fillTab
    /// P9-3 section 14: a stage run that shows a medley (once per run), Rehearse Medley
    /// (builder).
    case medley
}
