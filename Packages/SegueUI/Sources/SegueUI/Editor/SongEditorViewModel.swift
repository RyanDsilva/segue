import ChordPro
import Diagrams
import Editing
import Foundation
import Library
import MusicTheory
import Observation
import os
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

    public let mode: Mode
    public internal(set) var editorMode: EditorMode
    /// The per-song view toggles (persisted to the sidecar as `DisplayPrefs`).
    public internal(set) var options: DisplayOptions
    /// The rendered song (debounced ~100 ms after typing): preview, header, diagram strip.
    public private(set) var renderModel: RenderModel?
    /// Inline diagnostics for the text as of `renderModel`.
    public private(set) var diagnostics: [EditorDiagnostic] = []
    public private(set) var cursor = Cursor(line: 1, column: 1)
    /// Custom shapes flagged by the last "Apply transposition to source".
    public internal(set) var flaggedDefines: [DefineFlag] = []
    public private(set) var hasUnsavedChanges = false
    /// Whether the source is empty (shows the placeholder).
    public private(set) var isEmpty: Bool
    /// The song's `{capo}` (0 when none).
    public private(set) var capo = 0
    public private(set) var isSaving = false
    public var errorMessage: String?
    /// "n=40 max=3.1ms mean=1.2ms": keystroke processing times (acceptance criterion 9).
    public private(set) var keystrokeSummary = ""
    /// A palette chord "in hand" (display text): clicking a chord slot drops it there.
    public var armedChord: String?
    /// The library file name, for the status bar.
    public let fileName: String?

    /// The source text as of the last change (mirrors the text view).
    @ObservationIgnored public private(set) var source: String
    /// The current parse of `source`, rebuilt synchronously on every change.
    @ObservationIgnored public private(set) var snapshot: SourceSnapshot
    /// Visual mode's render model (no diagrams), rebuilt synchronously on every change while
    /// the canvas is up, so a gesture's result is on screen before the next event.
    @ObservationIgnored var canvasModel: RenderModel?
    /// The lyric line the edit being applied touches (`editLyrics`), for the canvas fast
    /// path. Cleared once the change lands.
    @ObservationIgnored var pendingLyricEdit: BlockPath?

    /// The text as last saved (or as opened): what "unsaved changes" compares against.
    @ObservationIgnored var originalSource: String
    /// The user's shape library, for diagram lookup after the song's `{define}`s.
    @ObservationIgnored let userShapes: UserShapeLibrary
    @ObservationIgnored let save: (String) async throws -> SongRecord
    @ObservationIgnored let persistPrefs: ((SongID, DisplayPrefs) async throws
        -> SongRecord)?
    @ObservationIgnored var savedPrefs: DisplayPrefs
    @ObservationIgnored var renderTask: Task<Void, Never>?
    @ObservationIgnored var prefsTask: Task<Void, Never>?
    @ObservationIgnored var revision = 0
    @ObservationIgnored var keystrokes = KeystrokeStats()

    #if os(macOS)
        @ObservationIgnored var sourceController: SourceEditorController?
        @ObservationIgnored var visualController: VisualEditorController?
        /// Main run loop busy time from the first keystroke on (the full cost of typing).
        @ObservationIgnored let hitches = MainThreadHitchMonitor()
    #endif

    /// - Parameters:
    ///   - save: persists the source (create or update) and returns the saved record.
    ///   - prefs: the song's stored display preferences.
    ///   - persistPrefs: writes display preferences to a song's sidecar. Edits persist each
    ///     toggle at once; a new song persists its toggles after its first save.
    public init(
        mode: Mode,
        source: String,
        prefs: DisplayPrefs = DisplayPrefs(),
        fileName: String? = nil,
        userShapes: UserShapeLibrary = .empty,
        persistPrefs: ((SongID, DisplayPrefs) async throws -> SongRecord)? = nil,
        save: @escaping (String) async throws -> SongRecord,
    ) {
        self.mode = mode
        self.userShapes = userShapes
        self.source = source
        originalSource = source
        self.save = save
        self.persistPrefs = persistPrefs
        self.fileName = fileName
        savedPrefs = prefs
        options = prefs.displayOptions
        snapshot = SourceSnapshot(text: source)
        isEmpty = source.isEmpty
        capo = max(snapshot.document.metadata.capo ?? 0, 0)
        // A new song starts as text; an existing one opens on the visual canvas (layout b).
        let blank = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        editorMode = blank ? .text : .visual
        let initial = RenderModel(
            document: snapshot.document,
            options: options,
            userShapes: userShapes,
        )
        renderModel = initial
        diagnostics = snapshot.diagnostics
        updateDerived(from: initial)
    }

    // MARK: State

    /// The parsed song, for titles and prompts.
    public var document: SongDocument {
        snapshot.document
    }

    /// Whether Save is allowed: a new song needs some text; an edit needs a change.
    public var canSave: Bool {
        !isSaving && hasUnsavedChanges
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
    }

    // MARK: Saving

    /// Saves; returns the saved record, or nil (with `errorMessage` set) on failure. One save
    /// runs at a time (`canSave` is false meanwhile); the text stays editable, and edits
    /// made during the save stay unsaved.
    @discardableResult
    public func commit() async -> SongRecord? {
        guard canSave else { return nil }
        // Let a pending display-prefs write land first (it moves the sidecar revision).
        await prefsTask?.value
        isSaving = true
        defer { isSaving = false }
        do {
            let record = try await save(source)
            errorMessage = nil
            // The editor stays open when the text changed while saving (typing is never
            // blocked by a save): from now on, unsaved means unlike what was just saved.
            originalSource = record.source
            updateDirty()
            if case .create = mode {
                let prefs = DisplayPrefs(options)
                if prefs != record.sidecar.displayPrefs, let persistPrefs {
                    _ = try await persistPrefs(record.id, prefs)
                }
            }
            return record
        } catch {
            errorMessage = UserMessage.describe(error)
            return nil
        }
    }

    func updateDirty() {
        let dirty = switch mode {
        case .create:
            !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .edit:
            source != originalSource
        }
        if dirty != hasUnsavedChanges {
            hasUnsavedChanges = dirty
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
        let revision = revision
        let userShapes = userShapes
        renderTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                (
                    RenderModel(
                        document: snapshot.document,
                        options: options,
                        userShapes: userShapes,
                    ),
                    snapshot.diagnostics,
                )
            }.value
            guard !Task.isCancelled, let self, self.revision == revision else { return }
            renderModel = rendered.0
            updateDerived(from: rendered.0)
            #if os(macOS)
                if editorMode == .visual, canvasModel?.sections != rendered.0.sections {
                    canvasModel = rendered.0
                    visualController?.reload()
                }
            #endif
            if diagnostics != rendered.1 {
                diagnostics = rendered.1
            }
            #if os(macOS)
                sourceController?.showDiagnostics(rendered.1, for: snapshot.text)
            #endif
            let summary = keystrokes.summary
            if summary != keystrokeSummary {
                keystrokeSummary = summary
            }
        }
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

    /// Records one key event's processing time. Shortcuts (⌘V, ⌘Z, ⌘↑) are not typing:
    /// they restart the measurement, so the stats describe the typing that follows.
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

    /// Clears the keystroke statistics (E2E measures a fresh run).
    func resetKeystrokeStats() {
        keystrokes = KeystrokeStats()
        keystrokeSummary = ""
        #if os(macOS)
            hitches.reset()
        #endif
    }

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
