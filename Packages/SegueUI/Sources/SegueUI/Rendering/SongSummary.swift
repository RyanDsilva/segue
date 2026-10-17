import ChordPro
import Foundation
import Library

/// Display strings derived from a song's metadata.
enum SongSummary {
    /// The title to show: `{title}`, else the file name.
    static func title(_ record: SongRecord) -> String {
        if let title = record.document.metadata.title?.trimmingCharacters(in: .whitespaces),
           !title.isEmpty
        {
            return title
        }
        let fileName = (record.relativePath as NSString).lastPathComponent
        return (fileName as NSString).deletingPathExtension
    }

    /// Artists joined for a list subtitle; nil when there are none.
    static func artist(_ metadata: Metadata) -> String? {
        let artists = metadata.artists
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return artists.isEmpty ? nil : artists.joined(separator: ", ")
    }

    /// Key, capo and tempo as one line, brand.md section 7: "G, capo 2, 96". Nil when the
    /// song has none of them.
    static func performanceLine(_ metadata: Metadata) -> String? {
        var parts: [String] = []
        if let key = metadata.key?.trimmingCharacters(in: .whitespaces), !key.isEmpty {
            parts.append(key)
        }
        if let capo = metadata.capo, capo > 0 {
            parts.append("capo \(capo)")
        }
        if let tempo = metadata.tempo, tempo > 0 {
            parts.append(tempo.rounded() == tempo ? String(Int(tempo)) : String(tempo))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
