import ChordPro
import Editing

extension SongEditorViewModel {
    /// `model` with one lyric line rebuilt from `document`, when only its lyric text
    /// changed (same chords in the same order). Nil when anything else changed, so the
    /// caller renders the whole model instead.
    static func canvas(
        _ model: RenderModel,
        patchingLine path: BlockPath,
        from document: SongDocument,
    ) -> RenderModel? {
        guard let line = document.line(at: path) else { return nil }
        var patched = model
        for sectionIndex in patched.sections.indices {
            let items = patched.sections[sectionIndex].items
            for (itemIndex, item) in items.enumerated() {
                guard case let .lyrics(old) = item, old.path == path else { continue }
                guard let updated = old.replacingLyrics(with: line) else { return nil }
                patched.sections[sectionIndex].items[itemIndex] = .lyrics(updated)
                return patched
            }
        }
        return nil
    }
}

extension RenderLine {
    /// This line with the text and chord offsets of `line`, keeping the display chords.
    /// Nil when the chords themselves differ.
    func replacingLyrics(with line: Line) -> RenderLine? {
        let originals = line.segments.compactMap(\.chord)
        guard originals == chords.map(\.original) else { return nil }
        var runs: [String] = []
        var offsets: [Int] = []
        var count = 0
        for segment in line.segments {
            if segment.chord != nil {
                offsets.append(count)
            }
            runs.append(segment.text)
            count += segment.text.count
        }
        var moved = chords
        for index in moved.indices {
            moved[index].offset = offsets[index]
        }
        return RenderLine(path: path, runs: runs, chords: moved)
    }
}

extension SongDocument {
    /// The lyric line at `path`, if that is one.
    func line(at path: BlockPath) -> Line? {
        guard blocks.indices.contains(path.block) else { return nil }
        switch (blocks[path.block], path.item) {
        case let (.line(line), nil):
            return line
        case let (.section(section), item?):
            guard section.items.indices.contains(item), case let .line(line) = section.items[item]
            else { return nil }
            return line
        default:
            return nil
        }
    }
}
