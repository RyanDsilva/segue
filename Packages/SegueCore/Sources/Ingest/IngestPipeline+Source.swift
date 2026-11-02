import ChordPro
import Foundation
import MusicTheory
import Plugins

// P9-4 spec 5.1: one ingest entry point for a web page or a lyrics record whose source
// already knows some fields. Pure and deterministic, like `ingest(_:origin:)`.

public extension IngestPipeline {
    /// Ingests `text` as `ingest(_:origin:)` does, then overlays the source's fields, source
    /// first: a plausible source title, artist credit, album, readable key or capo replaces
    /// what the text gave; a text value fills a field the source left empty; a field the text
    /// writes as a directive stays as written. Already-ChordPro text passes through untouched
    /// (the review may offer the source fields as suggestions only).
    static func ingest(_ text: String, origin: IngestOrigin, source: SourceFields) -> IngestResult {
        let base = ingest(text, origin: origin)
        guard !base.isAlreadyChordPro else { return base }
        var draft = base
        let skip = base.directiveFields

        if !skip.contains(.title), let title = plausible(source.title) {
            draft.metadata.title = title
        }
        if !skip.contains(.artist), let credit = source.artistCredit.flatMap(ArtistNames.cleaned),
           isPlausibleName(credit)
        {
            let split = ArtistNames.split(credit)
            if !split.parts.isEmpty {
                draft.metadata.artists = split.parts
                // A source's artist field is a credit (R173): its split shows as chips with
                // Keep as one; the text's own splits no longer describe the artists.
                draft.artistSplits = split.didSplit ? [split] : []
            }
        }
        if !skip.contains(.album), let album = plausible(source.album) {
            draft.metadata.album = album
        }
        if !skip.contains(.capo), let capo = source.capo, (1 ... 11).contains(capo) {
            draft.metadata.capo = capo
        }
        if !skip.contains(.key), let key = source.key.flatMap(SongKey.init(parsing:)) {
            // A site states the sounding key; with a capo `{key}` names the shapes key, by
            // the same rule as a pasted "Key" line (phase 1 ruling).
            draft.metadata.key = MetadataAssembly.keyToWrite(
                stated: key.name,
                capo: draft.metadata.capo ?? 0,
                chords: MetadataAssembly.writtenChords(draft.blocks),
            )
        }
        consumeHeadingLines(in: &draft, source: source)

        var result = assemble(draft)
        result.artistSplits = draft.artistSplits
        return result
    }

    /// A trimmed value that passes `isPlausibleName`, else nil.
    private static func plausible(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, isPlausibleName(value)
        else { return nil }
        return value
    }

    /// Step 6: the page's own heading ("Tum Hi Ho Chords by Arijit Singh") repeats source
    /// fields, so it is consumed as metadata, as a pasted header is. Only lines before the
    /// first content block are looked at, so a lyric that sings the title is never dropped.
    private static func consumeHeadingLines(in draft: inout IngestResult, source: SourceFields) {
        let headings = headingForms(source)
        guard !headings.isEmpty else { return }
        for blockIndex in draft.blocks.indices {
            guard draft.blocks[blockIndex].role != .content else { break }
            for lineIndex in draft.blocks[blockIndex].lines.indices {
                let line = draft.blocks[blockIndex].lines[lineIndex]
                guard headings.contains(headingKey(line.text)) else { continue }
                draft.blocks[blockIndex].lines[lineIndex].lineClass = .metadata
                draft.lines[line.index].lineClass = .metadata
                draft.consumedLines.insert(line.index)
            }
        }
    }

    /// The heading shapes a page prints from its own fields, as `headingKey` forms.
    private static func headingForms(_ source: SourceFields) -> Set<String> {
        var forms: Set<String> = []
        let artist = source.artistCredit.map { $0.trimmingCharacters(in: .whitespaces) }
        for title in [source.title].compactMap(\.self) {
            let title = title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            var shapes = [title, "\(title) chords", "\(title) lyrics", "\(title) chords and lyrics"]
            if let artist, !artist.isEmpty {
                shapes += [
                    "\(title) by \(artist)", "\(title) chords by \(artist)",
                    "\(title) lyrics by \(artist)", "\(title) - \(artist)",
                    "\(artist) - \(title)", "\(title) - \(artist) chords",
                    "\(title) \(artist) chords and lyrics",
                ]
            }
            forms.formUnion(shapes.map(headingKey))
        }
        if let artist, !artist.isEmpty {
            forms.formUnion(["by \(artist)", artist].map(headingKey))
        }
        return forms
    }

    /// Case-, diacritic- and space-insensitive form for comparing a line with a heading.
    private static func headingKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
