import Editing
import Foundation
import Library

/// Phase 2 (unit D): display strings for library rows and the builder.
extension SongSummary {
    /// The key the chords are written in: `{key}`, else the detected key; nil when neither.
    static func writtenKey(_ record: SongRecord) -> String? {
        if let key = record.document.metadata.key?.trimmingCharacters(in: .whitespaces),
           !key.isEmpty
        {
            return key
        }
        return KeyContext(document: record.document).writtenKey?.name
    }

    /// "Played once", "Played 3 times".
    static func timesPlayed(_ count: Int) -> String {
        count == 1 ? "Played once" : "Played \(count) times"
    }

    /// Tempo as a bare number ("96"); nil when the song has none.
    static func tempo(_ record: SongRecord) -> String? {
        guard let tempo = record.document.metadata.tempo, tempo > 0 else { return nil }
        return tempo.rounded() == tempo ? String(Int(tempo)) : String(tempo)
    }
}
