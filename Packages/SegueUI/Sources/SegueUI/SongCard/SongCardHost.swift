import ChordPro
import Editing
import Foundation
import Library
import Observation
import Support
import SwiftUI

/// Where a song card reads its song and sends its writes. Three hosts: the library detail
/// pane (writes the song's file, undoable from Edit > Undo), the open editor (the editor's
/// own undo stack and autosave, the same path as its top bar's capo stepper) and draft mode
/// (an in-memory source for the paste review sheet, no file I/O).
@MainActor
struct SongCardHost {
    /// The song as it is now.
    let document: SongDocument
    /// The card's identity: the song, or a draft's stand-in ID (Time it is keyed to it).
    let songID: SongID
    var isReadOnly = false
    /// The song's sidecar metadata, nil where the host has none (the editor strip).
    var metadata: SongMetadata?
    /// Artists already in the library, for the Artist field's completion.
    var knownArtists: [String] = []
    /// Tags already in the library, for the tag field.
    var knownTags: [String] = []
    /// Applies one operation as one undoable edit.
    let perform: (EditOperation) -> Void
    /// Changes the sidecar metadata (proficiency, tags) as one undoable edit.
    var editMetadata: ((@escaping (inout SongMetadata) -> Void) -> Void)?

    var values: SongCardValues {
        SongCardValues(document: document)
    }
}

extension SongCardHost {
    /// A draft: edits `source` (and `metadata`) in memory; nothing touches the disk.
    static func draft(
        source: Binding<String>,
        metadata: Binding<SongMetadata>? = nil,
        songID: SongID,
        knownArtists: [String] = [],
        knownTags: [String] = [],
    ) -> Self {
        SongCardHost(
            document: SourceSnapshot(text: source.wrappedValue).document,
            songID: songID,
            metadata: metadata?.wrappedValue,
            knownArtists: knownArtists,
            knownTags: knownTags,
            perform: { operation in
                let snapshot = SourceSnapshot(text: source.wrappedValue)
                guard let change = try? DocumentEditor.change(for: operation, in: snapshot)
                else { return }
                source.wrappedValue = source.wrappedValue.applying(change.edits)
            },
            editMetadata: metadata.map { binding in
                { change in change(&binding.wrappedValue) }
            },
        )
    }
}

extension SongID {
    /// A stand-in ID for a card whose song has none yet (a new song, a draft): Time it
    /// runs are keyed to it.
    static func standIn() -> SongID {
        SongID(ULID(
            timestamp: Date(),
            randomness: (0 ..< 10).map { _ in UInt8.random(in: 0 ... 255) },
        ))
    }
}

/// Asks a song card to focus one of its fields: Start blank (`.title`, P3-4) and the
/// missing-lengths list's Open Song (`.length`, P3-12). The card showing `songID` (or any
/// card, for nil) takes the request when it appears or when the request arrives.
@MainActor
@Observable
public final class SongCardFocusRouter {
    public struct Request: Equatable, Sendable {
        public let songID: SongID?
        public let field: SongCardField
        let serial: Int
    }

    /// The one router the app's cards observe.
    public static let shared = SongCardFocusRouter()

    public private(set) var pending: Request?
    @ObservationIgnored private var serial = 0

    public init() {}

    /// Focuses `field` on the card showing `songID` (nil: the next card that appears, for a
    /// new song that has no ID yet).
    public func focus(_ field: SongCardField, songID: SongID? = nil) {
        serial += 1
        pending = Request(songID: songID, field: field, serial: serial)
    }

    /// The card for `songID` takes the pending request meant for it, if any.
    func take(for songID: SongID) -> SongCardField? {
        guard let pending, pending.songID == nil || pending.songID == songID else { return nil }
        self.pending = nil
        return pending.field
    }
}
