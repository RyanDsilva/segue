import ChordPro
import Foundation
import Library
import Observation

/// The raw ChordPro editor: the text being edited, its live parse for the preview, and save.
@MainActor
@Observable
public final class SongEditorViewModel {
    public enum Mode: Equatable {
        case create
        case edit(SongID)
    }

    public let mode: Mode
    /// The ChordPro source being edited.
    public var source: String {
        didSet {
            if source != oldValue {
                reparse()
            }
        }
    }

    /// `source` parsed, for the preview.
    public private(set) var document: SongDocument
    /// Parser diagnostics for `source`.
    public private(set) var diagnostics: [Diagnostic]
    public private(set) var isSaving = false
    public var errorMessage: String?

    private let originalSource: String
    private let save: (String) async throws -> SongRecord

    /// - Parameter save: persists the source (create or update) and returns the saved record.
    public init(
        mode: Mode,
        source: String,
        save: @escaping (String) async throws -> SongRecord,
    ) {
        self.mode = mode
        self.source = source
        originalSource = source
        self.save = save
        (document, diagnostics) = ChordProParser.parse(source)
    }

    /// Whether the text differs from what was loaded.
    public var hasChanges: Bool {
        source != originalSource
    }

    /// Whether closing the editor now would lose work: a new song with some text, or an
    /// edit that changed the source.
    public var hasUnsavedChanges: Bool {
        switch mode {
        case .create:
            !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .edit:
            hasChanges
        }
    }

    /// Whether Save is allowed: a new song needs some text; an edit needs a change.
    public var canSave: Bool {
        !isSaving && hasUnsavedChanges
    }

    /// Saves; returns the saved record, or nil (with `errorMessage` set) on failure.
    @discardableResult
    public func commit() async -> SongRecord? {
        guard canSave else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            let record = try await save(source)
            errorMessage = nil
            return record
        } catch {
            errorMessage = UserMessage.describe(error)
            return nil
        }
    }

    private func reparse() {
        (document, diagnostics) = ChordProParser.parse(source)
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
