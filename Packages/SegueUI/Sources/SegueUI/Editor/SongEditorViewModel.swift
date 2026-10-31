import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
import Observation
import os
import Services
#if os(macOS)
    import AppKit
    import QuartzCore
#endif

/// The song editor: one ChordPro source (held by the text view, the single undoable store),
/// two views of it (text and visual), the per-song display options, and save.
///
/// Phase 1 interfaces, unit D flow: after every text change the editor builds a
/// `SourceSnapshot`; the preview, visual canvas and diagram strip draw from a `RenderModel`
/// of it. Visual gestures become `EditOperation`s, which `DocumentEditor` turns into minimal
/// `SourceChange`s applied through the text view as one undo group each.
@MainActor
@Observable
public final class SongEditorViewModel {
    public enum Mode: Equatable {
        case create
        case edit(SongID)
    }

    /// Text (ChordPro source + preview) or visual (chords over syllables).
    public enum EditorMode: Hashable, Sendable {
        case text
        case visual
    }

    /// The caret as a source line and column (1-based, UTF-16 columns).
    public struct Cursor: Equatable, Sendable {
        public var line: Int
        public var column: Int
    }

    /// `.create` until a new song's first autosave writes its file, then `.edit`.
    public internal(set) var mode: Mode
    /// Whether this editor session began on a new song (Start blank). Unlike `mode`, the
    /// first autosave does not change it, so layout keyed on it (the expanded song card)
    /// stays put while the user types instead of jumping when the file is first written.
    public let startedAsNew: Bool
    public internal(set) var editorMode: EditorMode {
        didSet {
            if editorMode == .visual, oldValue != .visual {
                SegueTips.donate(SegueTips.visualEditorOpened)
            }
        }
    }

    /// The per-song view toggles (persisted to the sidecar as `DisplayPrefs`).
    public internal(set) var options: DisplayOptions
    /// The song's stage memory (sidecar `live`); the editor sets its column choice.
    public internal(set) var livePrefs: LivePrefs
    /// The song's stage-only section notes (sidecar `cues`, P3-13); chart notes are the
    /// source's `{comment}` lines.
    public internal(set) var cues: [SongCue]
    /// The section notes sheet, open on one group (P3-13).
    public var sectionNotesRequest: SectionNotesRequest?
    /// The rendered song (debounced ~100 ms after typing): preview, header, diagram strip.
    public private(set) var renderModel: RenderModel?
    /// Inline diagnostics for the text as of `renderModel`.
    public private(set) var diagnostics: [EditorDiagnostic] = []
    public private(set) var cursor = Cursor(line: 1, column: 1)
    /// Custom shapes flagged by the last "Apply transposition to source".
    public internal(set) var flaggedDefines: [DefineFlag] = []
    /// Edits not on disk yet. While true the window shows its edited dot and macOS may not
    /// terminate the app suddenly.
    public internal(set) var hasUnsavedChanges = false {
        didSet {
            if hasUnsavedChanges != oldValue {
                SuddenTermination.hold(self, hasUnsavedChanges)
            }
        }
    }

    /// Whether the source is empty (shows the placeholder).
    public private(set) var isEmpty: Bool
    /// The song's `{capo}` (0 when none).
    public private(set) var capo = 0
    public private(set) var isSaving = false
    /// The last save failed for a reason other than a conflict (disk full, permission).
    public internal(set) var lastSaveFailed = false
    /// Why autosave is paused: the song's files changed on disk under the edit. Nothing is
    /// written until the user picks in the conflict bar.
    public internal(set) var conflict: SongConflict?
    /// "All changes saved" is showing (File > Save, 1.5 s).
    public internal(set) var isConfirmingSave = false
    public var errorMessage: String?
    /// "n=40 max=3.1ms mean=1.2ms": keystroke processing times (acceptance criterion 9).
    public private(set) var keystrokeSummary = ""
    /// A palette chord "in hand" (display text): clicking a chord slot drops it there.
    public var armedChord: String? {
        didSet {
            if let armedChord, armedChord != oldValue {
                recordPalette(.armed)
            }
        }
    }

    /// The library file name, for the status bar (follows a new song's renames).
    public internal(set) var fileName: String?

    /// The source text as of the last change (mirrors the text view).
    @ObservationIgnored public private(set) var source: String
    /// The current parse of `source`, rebuilt synchronously on every change.
    @ObservationIgnored public private(set) var snapshot: SourceSnapshot
    /// Visual mode's render model (no diagrams), rebuilt synchronously on every change while
    /// the canvas is up, so a gesture's result is on screen before the next event.
    /// The custom section kinds the library uses, most used first (R159): Custom...'s
    /// suggestions. Called only when Custom... opens; the library sets it.
    @ObservationIgnored var librarySectionKinds: () -> [SectionKind] = { [] }
    @ObservationIgnored var canvasModel: RenderModel?
    /// The lyric line the edit being applied touches (`editLyrics`), for the canvas fast
    /// path. Cleared once the change lands.
    @ObservationIgnored var pendingLyricEdit: BlockPath?

    /// The text as last saved (or as opened): what "unsaved changes" compares against.
    @ObservationIgnored var originalSource: String
    /// The user's shape library, for diagram lookup after the song's `{define}`s.
    @ObservationIgnored let userShapes: UserShapeLibrary
    /// Settings > Instrument (P8-4): the preview renders with its bass view; the visual
    /// canvas never does (decision 5). Observed, so a flip anywhere re-renders the preview.
    @ObservationIgnored let instrument: InstrumentProfileStore?
    /// Heard chords and walk-up auditions (P8-6); the library hands it over.
    @ObservationIgnored var sound: SoundSession?
    /// The Play along bar's model (P8-6 10.3), made on first use.
    @ObservationIgnored var playAlongStore: PlayAlong?
    /// Records analytics events (WS3 spec 5); the library hands over the app's hub.
    @ObservationIgnored public var services: ServicesHub = .disabled
    @ObservationIgnored let save: (String) async throws -> SongRecord
    @ObservationIgnored let persistPrefs: ((SongID, DisplayPrefs) async throws
        -> SongRecord)?
    @ObservationIgnored var savedPrefs: DisplayPrefs
    @ObservationIgnored let persistLivePrefs: ((SongID, LivePrefs) async throws
        -> SongRecord)?
    @ObservationIgnored var savedLivePrefs: LivePrefs
    @ObservationIgnored let persistCues: ((SongID, [SongCue]) async throws -> SongRecord)?
    /// The last stage-note sidecar write; the next one waits for it (P3-13).
    @ObservationIgnored var cuesTask: Task<Void, Never>?
    @ObservationIgnored var renderTask: Task<Void, Never>?
    /// The song's walk-up picks and feel (sidecar `bass`, P8-4b), writer, last write.
    var bassPrefs = BassPrefs()
    /// The song's saved fills (sidecar `parts`, P8-7c): a fill covers its changes in the
    /// preview, the Walk-ups list and play-along.
    var parts: [Part] = []
    /// Bass fills (P8-7d): the span selection, the fill sheet and the parts writer.
    @ObservationIgnored let fills = EditorFills()
    @ObservationIgnored var persistBassPrefs: ((SongID, BassPrefs) async throws -> SongRecord)?
    @ObservationIgnored var bassTask: Task<Void, Never>?
    @ObservationIgnored var prefsTask: Task<Void, Never>?
    @ObservationIgnored var revision = 0
    @ObservationIgnored var keystrokes = KeystrokeStats()
    /// Saves edits on its own (WS2a 3.4); `flush()` saves now.
    @ObservationIgnored let autosave: AutosaveScheduler
    @ObservationIgnored var confirmationTask: Task<Void, Never>?

    #if os(macOS)
        @ObservationIgnored var sourceController: SourceEditorController?
        @ObservationIgnored var visualController: VisualEditorController?
    #endif
    #if os(macOS) && DEBUG
        /// Main run loop busy time from the first keystroke on (the full cost of typing).
        @ObservationIgnored let hitches = MainThreadHitchMonitor()
    #endif

    /// - Parameters:
    ///   - save: persists the source (create or update) and returns the saved record.
    ///   - prefs: the song's stored display preferences.
    ///   - persistPrefs: writes display preferences to a song's sidecar. Edits persist each
    ///     toggle at once; a new song persists its toggles after its first save.
    ///   - livePrefs, persistLivePrefs: the song's stage memory and its writer, the same way.
    ///   - cues, persistCues: the song's stage-only section notes and their writer.
    public init(
        mode: Mode,
        source: String,
        prefs: DisplayPrefs = DisplayPrefs(),
        livePrefs: LivePrefs = LivePrefs(),
        fileName: String? = nil,
        userShapes: UserShapeLibrary = .empty,
        persistPrefs: ((SongID, DisplayPrefs) async throws -> SongRecord)? = nil,
        persistLivePrefs: ((SongID, LivePrefs) async throws -> SongRecord)? = nil,
        cues: [SongCue] = [],
        persistCues: ((SongID, [SongCue]) async throws -> SongRecord)? = nil,
        autosave timing: AutosaveTiming = .standard,
        instrument: InstrumentProfileStore? = nil,
        save: @escaping (String) async throws -> SongRecord,
    ) {
        autosave = timing.scheduler()
        self.instrument = instrument
        self.mode = mode
        startedAsNew = mode == .create
        self.userShapes = userShapes
        self.source = source
        originalSource = source
        self.save = save
        self.persistPrefs = persistPrefs
        self.persistLivePrefs = persistLivePrefs
        self.fileName = fileName
        savedPrefs = prefs
        self.livePrefs = livePrefs
        savedLivePrefs = livePrefs
        self.cues = cues
        self.persistCues = persistCues
        options = prefs.displayOptions
        snapshot = SourceSnapshot(text: source)
        isEmpty = source.isEmpty
        capo = max(snapshot.document.metadata.capo ?? 0, 0)
        // A new song starts as text; an existing one opens on the visual canvas (layout b).
        let blank = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        editorMode = blank ? .text : .visual
        let initial = Self.renderModels(
            snapshot.document, options: options, bass: instrument?.bassView, userShapes: userShapes,
        ).preview
        renderModel = initial
        diagnostics = snapshot.diagnostics
        updateDerived(from: initial)
        autosave.save = { [weak self] in await self?.saveNow() ?? true }
        observeInstrument()
    }

    // MARK: State

    /// The parsed song, for titles and prompts.
    public var document: SongDocument {
        snapshot.document
    }

    // Values derived from the render, stored and only assigned when they change, so a
    // keystroke's re-render invalidates just the views that show what changed (the editor
    // body never depends on the whole `renderModel`).

    /// The song title for the window ("Untitled" until it has one).
    public private(set) var title = "Untitled"
    /// The displayed key's name ("Ab"), for the transpose readout.
    public private(set) var displayKeyName: String?
    /// The diagram strip entries.
    public private(set) var diagrams: [RenderDiagram] = []
    /// The tuning diagrams use: the song's `{meta: tuning}`, else the sidecar's.
    public private(set) var tuning: Tuning = .standard
    /// The chords shown in the palette: unique, in order of first appearance, as displayed
    /// (letter names in the display key, Nashville numbers in Nashville view).
    public private(set) var paletteChords: [String] = []

    func updateDerived(from model: RenderModel) {
        let rawTitle = model.header.title?.trimmingCharacters(in: .whitespaces) ?? ""
        let newTitle = rawTitle.isEmpty ? "Untitled" : rawTitle
        if newTitle != title {
            title = newTitle
        }
        let keyName = model.transform.displayKey?.name
        if keyName != displayKeyName {
            displayKeyName = keyName
        }
        if model.diagrams != diagrams {
            diagrams = model.diagrams
        }
        if model.tuning != tuning {
            tuning = model.tuning
        }
        let chords = computePaletteChords()
        if chords != paletteChords {
            paletteChords = chords
        }
        fillsFollowRender()
    }

    // MARK: Saving

    /// One save of the current text (the autosave step); returns the saved record, or nil
    /// when there was nothing to save or the save failed. A conflict pauses autosave and
    /// sets `conflict`; another failure sets `lastSaveFailed` and `errorMessage` (retried
    /// on the next change or flush). The text stays editable; edits made during the save
    /// stay unsaved and are saved next.
    @discardableResult
    func commit() async -> SongRecord? {
        guard hasUnsavedChanges, !isSaving, conflict == nil else { return nil }
        // Let a pending display-prefs write land first (it moves the sidecar revision).
        await prefsTask?.value
        isSaving = true
        defer { isSaving = false }
        do {
            let record = try await save(source)
            errorMessage = nil
            lastSaveFailed = false
            originalSource = record.source
            fileName = record.relativePath
            updateDirty()
            if case .create = mode {
                mode = .edit(record.id)
                let prefs = DisplayPrefs(options)
                if prefs != record.sidecar.displayPrefs, let persistPrefs {
                    _ = try await persistPrefs(record.id, prefs)
                }
                if livePrefs != record.sidecar.live, let persistLivePrefs {
                    _ = try await persistLivePrefs(record.id, livePrefs)
                }
            }
            return record
        } catch {
            noteSaveFailure(error)
            return nil
        }
    }

    // MARK: Text changes

    /// Every change of the source text (typing, tree edits, undo/redo). Called with other
    /// text (e.g. restoring an unsaved edit), it replaces the text view's content.
    func sourceTextDidChange(_ text: String) {
        #if os(macOS)
            if let sourceController, sourceController.text != text {
                // Goes through the text view (undoable) and comes back here.
                sourceController.replaceAll(with: text)
                return
            }
        #endif
        source = text
        snapshot = SourceSnapshot(text: text)
        if isEmpty != text.isEmpty {
            isEmpty = text.isEmpty
        }
        let newCapo = max(snapshot.document.metadata.capo ?? 0, 0)
        if newCapo != capo {
            capo = newCapo
        }
        revision += 1
        updateDirty()
        refreshCanvas()
        scheduleRender(delay: .milliseconds(100))
    }

    /// Rebuilds the visual canvas from the current snapshot (synchronously).
    func refreshCanvas() {
        #if os(macOS)
            guard editorMode == .visual else {
                canvasModel = nil
                return
            }
            if let path = pendingLyricEdit, let current = canvasModel,
               let patched = Self.canvas(current, patchingLine: path, from: snapshot.document)
            {
                // Typing in a lyric line: only that line changed. The background render
                // replaces this with a full model ~100 ms later.
                canvasModel = patched
            } else {
                var canvasOptions = options
                canvasOptions.showDiagrams = false
                canvasModel = RenderModel(document: snapshot.document, options: canvasOptions)
            }
            visualController?.reload()
        #endif
    }

    /// Re-renders the preview and diagnostics off the main thread after `delay`.
    func scheduleRender(delay: Duration) {
        renderTask?.cancel()
        let snapshot = snapshot
        let options = options
        let bass = BassRender(view: instrument?.bassView, prefs: bassPrefs, parts: parts)
        let needsCanvas = bass.view?.notes == true && editorMode == .visual
        let revision = revision
        let userShapes = userShapes
        renderTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let rendered = await Self.render(snapshot, options, bass, needsCanvas, userShapes)
            guard !Task.isCancelled, let self, self.revision == revision else { return }
            renderModel = rendered.preview
            updateDerived(from: rendered.preview)
            #if os(macOS)
                if editorMode == .visual, rendered.canvas.transform.options.bass?.notes != true,
                   canvasModel?.sections != rendered.canvas.sections
                {
                    canvasModel = rendered.canvas
                    visualController?.reload()
                }
            #endif
            if diagnostics != rendered.diagnostics {
                diagnostics = rendered.diagnostics
            }
            #if os(macOS)
                sourceController?.showDiagnostics(rendered.diagnostics, for: snapshot.text)
            #endif
            let summary = keystrokes.summary
            if summary != keystrokeSummary {
                keystrokeSummary = summary
            }
        }
    }

    #if DEBUG
        /// Records one key event's processing time (Debug only; the E2E suite reads the
        /// summary). Shortcuts (⌘V, ⌘Z, ⌘↑) are not typing: they restart the measurement,
        /// so the stats describe the typing that follows.
        func recordKeystroke(_ seconds: TimeInterval, isShortcut: Bool = false) {
            #if os(macOS)
                hitches.start()
                if isShortcut {
                    keystrokes = KeystrokeStats()
                    hitches.reset()
                    return
                }
                keystrokes.busyMaximum = hitches.maximum
            #endif
            if seconds > 0.008 {
                EditorPerformance.log
                    .notice("slow keystroke \(seconds * 1000, format: .fixed(precision: 1)) ms")
            }
            keystrokes.record(seconds)
        }
    #endif

    /// Placeholder shown in an empty editor.
    public static let placeholder = """
    {title: Song title}
    {artist: Artist}
    {key: G}

    {start_of_verse}
    [G]Lyrics with [C]chords in [D]brackets
    {end_of_verse}
    """
}

// MARK: - Caret

extension SongEditorViewModel {
    /// Clears the keystroke statistics (E2E measures a fresh run).
    func resetKeystrokeStats() {
        keystrokes = KeystrokeStats()
        keystrokeSummary = ""
        #if os(macOS) && DEBUG
            hitches.reset()
        #endif
    }

    /// Updates the status bar's line and column for a source offset.
    func sourceCaretDidMove(to offset: Int) {
        #if os(macOS)
            let textView = sourceEditor.textView
            let line = textView.lineIndex(forOffset: offset)
            let start = textView.lineStarts.indices.contains(line) ? textView.lineStarts[line] : 0
            let updated = Cursor(line: line + 1, column: offset - start + 1)
            if updated != cursor {
                cursor = updated
            }
        #endif
    }
}
