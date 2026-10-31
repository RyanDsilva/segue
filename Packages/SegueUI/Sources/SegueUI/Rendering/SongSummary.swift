import ChordPro
import Diagrams
import Editing
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

    /// The song as its display toggles render it (sidecar prefs), with the user's bass-note
    /// view when it is on (P8-4 6.3). The live view passes `showDiagrams: false` (its strip
    /// is phase 2).
    static func renderModel(
        _ record: SongRecord,
        showDiagrams: Bool = true,
        userShapes: UserShapeLibrary = .empty,
        bass: BassView? = nil,
    ) -> RenderModel {
        var options = record.sidecar.displayPrefs.displayOptions
        options.bass = bass
        options.showDiagrams = options.showDiagrams && showDiagrams
        // Walk-ups in the bass-note view: the song's pick, else the top candidate (P8-4b);
        // none on a change a saved fill covers (P8-7c).
        return BassLine.annotated(
            RenderModel(document: record.document, options: options, userShapes: userShapes),
            document: record.document,
            prefs: record.sidecar.bass,
            parts: record.sidecar.parts,
        )
    }

    /// Artist and performance line for a rendered song: "Artist  ·  G, capo 2, 96". The key
    /// is the displayed key (transposed, Nashville header in Nashville view), marked when
    /// it was inferred; the capo only shows in Shapes mode, where the chords are shapes.
    static func subtitle(_ model: RenderModel) -> String {
        let artists = model.header.artists
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return [
            artists.isEmpty ? nil : artists.joined(separator: ", "),
            performanceLine(model),
        ].compactMap(\.self).joined(separator: "  ·  ")
    }

    /// Displayed key, capo (Shapes mode) and tempo: "G, capo 2, 96"; nil when none. In the
    /// bass-note view the key is the sounding key and there is no capo (the notes are not
    /// shapes), exactly as in Concert mode.
    static func performanceLine(_ model: RenderModel) -> String? {
        let header = model.header
        var parts: [String] = []
        if let key = header.key, !key.isEmpty {
            switch header.keyStatus {
            case .declared, .unknown: parts.append(key)
            case .inferred: parts.append("\(key) (inferred)")
            case .ambiguous: parts.append("\(key) (ambiguous)")
            }
        }
        let options = model.transform.options
        if let capo = header.capo, capo > 0, options.capoMode == .shapes,
           options.bass?.notes != true
        {
            parts.append("capo \(capo)")
        }
        if let tempo = header.tempo, tempo > 0 {
            parts.append(tempo.rounded() == tempo ? String(Int(tempo)) : String(tempo))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
