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
    /// The song card's Time it timer was stopped into a length (R91).
    case timeIt
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
    /// here" saved, a song's feel set (editor or library).
    case walkUps
    case walkUpPick
    case songFeel
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
}
