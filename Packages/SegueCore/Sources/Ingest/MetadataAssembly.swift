import ChordPro
import Foundation
import MusicTheory

/// Collects metadata from directives, key/value lines and the title block, decides which
/// lines it consumed, and resolves the `{key}` to write when a capo is stated.
enum MetadataAssembly {
    struct Extraction {
        var metadata: IngestMetadata
        var directiveFields: Set<MetadataKey>
        var consumedLines: Set<Int>
        /// Credit-line and header artists that split into 2+ (P8-8 section 3.7).
        var artistSplits: [ArtistSplit]
    }

    /// Reads metadata from `blocks`, marking title-block lines it used as `.metadata`.
    static func extract(_ blocks: inout [IngestBlock]) -> Extraction {
        var collector = Collector()
        for block in blocks {
            for line in block.lines where line.lineClass == .directive {
                collector.addDirective(line.text)
            }
        }
        for blockIndex in blocks.indices {
            let isTitleBlock = blocks[blockIndex].role == .metadata
                && blocks[..<blockIndex].allSatisfy { $0.role != .content }
            var previousWasTitle = false
            var seenText = false
            for lineIndex in blocks[blockIndex].lines.indices {
                let line = blocks[blockIndex].lines[lineIndex]
                if line.lineClass == .metadata,
                   let fields = MetadataExtractor.keyValueFields(line.text)
                {
                    collector.add(fields, line: line.index)
                    previousWasTitle = false
                    continue
                }
                guard isTitleBlock, line.lineClass == .unknown else { continue }
                var fields = MetadataExtractor.titleFields(line.text, isFirst: !seenText) ?? []
                if fields.isEmpty, previousWasTitle, collector.metadata.artists.isEmpty,
                   MetadataExtractor.isNameLike(line.text),
                   // The title again (often in capitals) is not the artist.
                   line.text.trimmingCharacters(in: .whitespaces).lowercased()
                   != collector.metadata.title?.lowercased()
                {
                    fields = [.artist(line.text.trimmingCharacters(in: .whitespaces))]
                }
                seenText = true
                previousWasTitle = fields.contains {
                    if case .title = $0 {
                        true
                    } else {
                        false
                    }
                }
                if collector.add(fields, line: line.index) {
                    blocks[blockIndex].lines[lineIndex].lineClass = .metadata
                }
            }
        }
        return Extraction(
            metadata: collector.resolved(chords: writtenChords(blocks)),
            directiveFields: collector.directiveFields,
            consumedLines: collector.consumed,
            artistSplits: collector.artistSplits,
        )
    }

    /// The metadata directives to write at the top, skipping fields the source already has.
    static func directives(for metadata: IngestMetadata, skipping: Set<MetadataKey>) -> [String] {
        var lines: [String] = []
        func emit(_ key: MetadataKey, _ value: String?) {
            guard let value, !skipping.contains(key) else { return }
            lines.append("{\(key.rawValue): \(value)}")
        }
        emit(.title, metadata.title)
        if !skipping.contains(.artist) {
            lines += metadata.artists.map { "{artist: \($0)}" }
        }
        emit(.composer, metadata.composer)
        emit(.lyricist, metadata.lyricist)
        emit(.album, metadata.album)
        emit(.key, metadata.key)
        emit(.capo, metadata.capo.map(String.init))
        emit(.tempo, metadata.tempo.map(String.init))
        return lines
    }

    /// A bare-lyrics sheet's first block is its title block when it is one short line, or
    /// a title line followed only by `by X` and key/value lines.
    static func isTitleBlock(_ block: IngestBlock) -> Bool {
        let lines = block.lines.map(\.text)
        guard (1 ... 3).contains(lines.count),
              let first = MetadataExtractor.titleFields(lines[0], isFirst: true), !first.isEmpty
        else { return false }
        if lines.count == 1 {
            return true
        }
        return lines.dropFirst().allSatisfy { line in
            MetadataExtractor.titleFields(line, isFirst: false) != nil
                || MetadataExtractor.keyValueFields(line) != nil
        }
    }

    /// Chords as written (chord lines, inline chords, header chords), for the capo rule.
    private static func writtenChords(_ blocks: [IngestBlock]) -> [ChartChord] {
        var texts: [String] = []
        for block in blocks where block.role == .content {
            if let trailing = block.header?.trailingChords {
                texts += ChordLines.tokens(trailing).map(\.text)
            }
            for line in block.lines {
                if line.lineClass == .chordLine {
                    texts += ChordLines.tokens(line.text).map(\.text)
                } else if line.lineClass == .lyricLine {
                    texts += ChordLines.inlineChords(line.text)
                }
            }
        }
        return texts.compactMap { ChordToken(parsing: $0).chord }
    }
}

/// First-wins accumulation of metadata fields.
private struct Collector {
    var metadata = IngestMetadata()
    var directiveFields: Set<MetadataKey> = []
    var consumed: Set<Int> = []
    var statedKey: String?
    var shapesKey: String?
    var keyFromDirective = false
    var artistSplits: [ArtistSplit] = []

    /// Adds `fields` from source line `line`; true when at least one was new.
    @discardableResult
    mutating func add(_ fields: [MetadataField], line: Int) -> Bool {
        var used = false
        for field in fields where add(field) {
            used = true
        }
        if used {
            consumed.insert(line)
        }
        return used
    }

    /// A field from a credit line or a header: a combined artist splits (R172, R173). A
    /// field from an `{artist}` directive comes through `addDirective` and stays whole.
    @discardableResult
    private mutating func add(_ field: MetadataField) -> Bool {
        guard case let .artist(value) = field else { return store(field) }
        let split = ArtistNames.split(value)
        guard !split.parts.isEmpty else { return store(field) }
        var used = false
        for part in split.parts where store(.artist(part)) {
            used = true
        }
        if used, split.didSplit {
            artistSplits.append(split)
        }
        return used
    }

    /// Stores one field as given (first wins; artists deduplicated).
    @discardableResult
    private mutating func store(_ field: MetadataField) -> Bool {
        switch field {
        case let .title(value): return Self.set(&metadata.title, value)
        case let .artist(value):
            guard !metadata.artists.contains(value) else { return false }
            metadata.artists.append(value)
            return true
        case let .composer(value): return Self.set(&metadata.composer, value)
        case let .lyricist(value): return Self.set(&metadata.lyricist, value)
        case let .album(value): return Self.set(&metadata.album, value)
        case let .key(value): return Self.set(&statedKey, value)
        case let .capo(value): return Self.set(&metadata.capo, value)
        case let .shapesKey(value): return Self.set(&shapesKey, value)
        case let .tempo(value): return Self.set(&metadata.tempo, value)
        }
    }

    private static func set<T>(_ slot: inout T?, _ value: T) -> Bool {
        guard slot == nil else { return false }
        slot = value
        return true
    }

    /// Records a `{name: value}` directive line from the source.
    mutating func addDirective(_ text: String) {
        let pattern = /\s*\{\s*([A-Za-z_]+)\s*(?:[:\s]\s*(.*?))?\s*\}\s*/
        guard let match = text.wholeMatch(of: pattern) else { return }
        let value = match.output.2.map(String.init) ?? ""
        let name = String(match.output.1).lowercased()
        guard let key = MetadataKey(rawValue: name == "t" ? "title" : name), !value.isEmpty
        else { return }
        directiveFields.insert(key)
        keyFromDirective = keyFromDirective || key == .key
        if let field = Self.field(key, value) {
            store(field)
        }
    }

    private static func field(_ key: MetadataKey, _ value: String) -> MetadataField? {
        switch key {
        case .album: .album(value)
        case .artist: .artist(value)
        case .capo: Int(value).map(MetadataField.capo)
        case .composer: .composer(value)
        case .key: .key(value)
        case .lyricist: .lyricist(value)
        case .tempo: Int(value).map(MetadataField.tempo)
        case .title: .title(value)
        }
    }

    /// The final metadata. With a capo, `{key}` names the shapes key (phase 1 ruling): an
    /// explicit "C shapes" note wins; else the stated key is taken as the shapes key when it
    /// fits the written chords better than the stated key lowered by the capo.
    func resolved(chords: [ChartChord]) -> IngestMetadata {
        var result = metadata
        result.key = statedKey
        guard !keyFromDirective, let capo = metadata.capo, capo > 0 else { return result }
        if let shapesKey {
            result.key = shapesKey
            return result
        }
        guard let text = statedKey, let stated = SongKey(parsing: text),
              let detection = KeyDetector.detect(chords)
        else { return result }
        let lowered = stated.transposed(by: -capo)
        let rank: (SongKey) -> Int = { key in
            detection.ranking.firstIndex {
                $0.key.tonic.pitchClass == key.tonic.pitchClass && $0.key.mode == key.mode
            } ?? Int.max
        }
        if rank(lowered) < rank(stated) {
            result.key = lowered.name
        }
        return result
    }
}
