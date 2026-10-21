// Owner: unit C (Editing). Turns one `EditOperation` into line-local text replacements.

import ChordPro
import Diagrams
import MusicTheory

/// Plans the text for one operation. Lyric-line operations rebuild only the touched lines
/// from their `LyricLineModel` (which reproduces untouched spelling exactly); directive
/// operations re-spell one directive line or insert/delete whole lines. `EditBuilder` then
/// trims every replacement to the bytes that really change.
struct EditPlanner {
    let snapshot: SourceSnapshot
    var builder: EditBuilder
    /// Caret after the edit: an offset in the pre-edit text plus an offset into the text
    /// replaced there.
    var caret: (anchor: Int, extra: Int)?

    init(snapshot: SourceSnapshot) {
        self.snapshot = snapshot
        builder = EditBuilder(text: snapshot.text)
    }

    func change(actionName: String) -> SourceChange {
        let edits = builder.edits()
        let selection = caret.map { caret -> Range<Int> in
            let shift = edits.filter { $0.range.lowerBound < caret.anchor }
                .reduce(0) { $0 + $1.replacement.utf16.count - $1.range.count }
            let offset = caret.anchor + shift + caret.extra
            return offset ..< offset
        }
        return SourceChange(edits: edits, actionName: actionName, selectionAfter: selection)
    }

    // MARK: - Chords and lyrics

    mutating func insertChord(_ chord: String, at position: LyricPosition) throws(EditError) {
        try Self.validate(chord)
        var model = try lineModel(position.line)
        try check(position, in: model)
        // A chord already on that character is replaced, never stacked (phase 1 build
        // rulings); an authored stack (`[A][B]text`) collapses to the new chord.
        model.chords.removeAll { $0.offset == position.offset }
        model.insert(chord, at: position.offset)
        let index = model.chords.lastIndex { $0.offset == position.offset && $0.text == chord }
        try rewrite(position.line, as: model, caretAfterChord: index)
    }

    mutating func replaceChord(_ ref: ChordRef, with chord: String) throws(EditError) {
        try Self.validate(chord)
        var model = try lineModel(ref.line)
        guard model.chords.indices.contains(ref.index) else { throw .invalidChord(ref) }
        model.chords[ref.index].text = chord
        try rewrite(ref.line, as: model, caretAfterChord: ref.index)
    }

    mutating func deleteChord(_ ref: ChordRef) throws(EditError) {
        var model = try lineModel(ref.line)
        guard model.chords.indices.contains(ref.index) else { throw .invalidChord(ref) }
        let removed = model.chords.remove(at: ref.index)
        try rewrite(ref.line, as: model, caretAtLyric: removed.offset)
    }

    mutating func moveChord(
        _ ref: ChordRef,
        to position: LyricPosition,
        keepingOriginal: Bool,
    ) throws(EditError) {
        var source = try lineModel(ref.line)
        guard source.chords.indices.contains(ref.index) else { throw .invalidChord(ref) }
        let chord = source.chords[ref.index].text
        if position.line == ref.line {
            try check(position, in: source)
            if !keepingOriginal {
                source.chords.remove(at: ref.index)
            }
            source.insert(chord, at: position.offset)
            let index = source.chords.lastIndex { $0.offset == position.offset && $0.text == chord }
            return try rewrite(ref.line, as: source, caretAfterChord: index)
        }
        var target = try lineModel(position.line)
        try check(position, in: target)
        if !keepingOriginal {
            source.chords.remove(at: ref.index)
            try rewrite(ref.line, as: source)
        }
        target.insert(chord, at: position.offset)
        let index = target.chords.lastIndex { $0.offset == position.offset && $0.text == chord }
        try rewrite(position.line, as: target, caretAfterChord: index)
    }

    mutating func editLyrics(
        _ path: BlockPath,
        range: Range<Int>,
        replacement: String,
    ) throws(EditError) {
        let model = try lineModel(path)
        guard range.lowerBound >= 0, range.upperBound <= model.lyrics.count else {
            throw .offsetOutOfRange(LyricPosition(line: path, offset: range.upperBound))
        }
        let inserted = Array(replacement)
        let delta = inserted.count - range.count
        let chords = model.chords.map { chord in
            var chord = chord
            if chord.offset >= range.upperBound {
                chord.offset += delta
            } else if chord.offset > range.lowerBound {
                chord.offset = range.lowerBound
            }
            return chord
        }
        var lyrics = model.lyrics
        lyrics.replaceSubrange(range, with: inserted)
        // Chords pulled to the start of a removed range sit before the replacement text;
        // `LyricLineModel` places chords before the character at their offset, so the ones
        // at `range.lowerBound` keep their relative order with the shifted ones.
        let edited = LyricLineModel(lyrics: lyrics, chords: chords)
        try Self.ensureLyricLine(edited.render().text, chords: chords.count, path: path)
        try rewrite(path, as: edited, caretAtLyric: range.lowerBound + inserted.count)
    }

    mutating func splitLine(at position: LyricPosition) throws(EditError) {
        let model = try lineModel(position.line)
        try check(position, in: model)
        let first = LyricLineModel(
            lyrics: Array(model.lyrics[..<position.offset]),
            chords: model.chords.filter { $0.offset < position.offset },
        )
        let second = LyricLineModel(
            lyrics: Array(model.lyrics[position.offset...]),
            chords: model.chords.filter { $0.offset >= position.offset }.map {
                LyricLineModel.Chord(text: $0.text, offset: $0.offset - position.offset)
            },
        )
        try Self.ensureLyricLine(
            first.render().text,
            chords: first.chords.count,
            path: position.line,
        )
        try Self.ensureLyricLine(
            second.render().text,
            chords: second.chords.count,
            path: position.line,
        )
        let line = try sourceLine(position.line)
        let ending = line.hasEnding ? line.ending : snapshot.map.defaultEnding
        let head = first.render().text + ending
        builder.replace(line.contentRange, with: head + second.render().text)
        caret = (line.start, head.utf16.count)
    }

    mutating func joinWithPrevious(_ path: BlockPath) throws(EditError) {
        _ = try lineModel(path)
        let previous: BlockPath
        if let item = path.item {
            guard item > 0 else { throw .wrongBlockKind(path) }
            previous = BlockPath(block: path.block, item: item - 1)
        } else {
            guard path.block > 0 else { throw .wrongBlockKind(path) }
            previous = BlockPath(block: path.block - 1)
        }
        guard snapshot.layout(of: previous) != nil else { throw .wrongBlockKind(path) }
        let upper = try sourceLine(path)
        let lower = try sourceLine(previous)
        builder.replace(lower.contentEnd ..< upper.start, with: "")
        caret = (lower.contentEnd, 0)
    }

    // MARK: - Directives

    mutating func setSectionLabel(_ path: BlockPath, label: String?) throws(EditError) {
        guard path.item == nil, case .section = snapshot.block(at: path) else {
            throw snapshot.block(at: path) == nil ? .invalidPath(path) : .wrongBlockKind(path)
        }
        let line = try sourceLine(path)
        guard let directive = DirectiveLine(line.text) else { throw .wrongBlockKind(path) }
        let value = label.flatMap { $0.isEmpty ? nil : $0 }
        builder.replace(line.contentRange, with: directive.replacingValue(with: value))
    }

    mutating func setDirective(name: String, value: String?) {
        let existing = snapshot.directiveLines(named: name).first
        setDirectiveLine(existing?.line, name: name, value: value)
    }

    mutating func setMeta(name: String, value: String?) {
        let existing = snapshot.directiveLines(named: "meta").first { entry in
            Self.firstWord(entry.directive.value)?.lowercased() == name.lowercased()
        }
        let spelled = existing.flatMap { Self.firstWord($0.directive.value) } ?? name
        setDirectiveLine(existing?.line, name: "meta", value: value.map { "\(spelled) \($0)" })
    }

    mutating func setDefine(_ definition: ChordDefinition) {
        let lines = snapshot.defineLines.filter { $0.name == definition.name }
        setDirectiveLine(lines.first?.line, name: "define", value: definition.directiveValue)
        for line in lines.dropFirst() {
            deleteLine(line.line)
        }
    }

    mutating func removeDefine(name: String) {
        for line in snapshot.defineLines where line.name == name {
            deleteLine(line.line)
        }
    }

    // MARK: - Helpers

    /// Re-spells the directive on `line` (or deletes it for `nil`); inserts a new one after
    /// the leading metadata directives when there is no line.
    private mutating func setDirectiveLine(_ line: Int?, name: String, value: String?) {
        if let line {
            let source = snapshot.map.lines[line]
            guard let value else { return deleteLine(line) }
            guard let directive = DirectiveLine(source.text) else { return }
            builder.replace(source.contentRange, with: directive.replacingValue(with: value))
            return
        }
        guard let value else { return }
        snapshot.insertLine(
            DirectiveLine.canonical(name: name, value: value),
            afterLine: snapshot.leadingMetadataEnd,
            into: &builder,
        )
    }

    /// Removes a whole line. A last line without an ending takes the previous ending with it.
    mutating func deleteLine(_ index: Int) {
        let line = snapshot.map.lines[index]
        if !line.hasEnding, index > 0 {
            builder.replace(snapshot.map.lines[index - 1].contentEnd ..< line.end, with: "")
        } else {
            builder.replace(line.start ..< line.end, with: "")
        }
    }

    func sourceLine(_ path: BlockPath) throws(EditError) -> SourceLine {
        guard let index = snapshot.map.lineOfPath[path] else { throw .invalidPath(path) }
        return snapshot.map.lines[index]
    }

    private func lineModel(_ path: BlockPath) throws(EditError) -> LyricLineModel {
        guard let block = snapshot.block(at: path) else { throw .invalidPath(path) }
        guard case .line = block else { throw .wrongBlockKind(path) }
        if snapshot.isVerbatim(path) {
            throw .readOnlyBlock(path)
        }
        guard let layout = snapshot.layout(of: path) else { throw .invalidPath(path) }
        return LyricLineModel(layout)
    }

    private func check(_ position: LyricPosition, in model: LyricLineModel) throws(EditError) {
        guard position.offset >= 0, position.offset <= model.lyrics.count else {
            throw .offsetOutOfRange(position)
        }
    }

    private mutating func rewrite(
        _ path: BlockPath,
        as model: LyricLineModel,
        caretAfterChord chord: Int? = nil,
        caretAtLyric lyric: Int? = nil,
    ) throws(EditError) {
        let line = try sourceLine(path)
        let rendered = model.render()
        builder.replace(line.contentRange, with: rendered.text)
        if let chord, rendered.chordEnds.indices.contains(chord) {
            caret = (line.start, rendered.chordEnds[chord])
        } else if let lyric, rendered.lyricStarts.indices.contains(lyric) {
            caret = (line.start, rendered.lyricStarts[lyric])
        }
    }

    /// `text` must still parse as a lyric line (or a blank one) with exactly `chords`
    /// chords: typed text never becomes a `#` comment, a directive or a chord.
    static func ensureLyricLine(_ text: String, chords: Int, path: BlockPath) throws(EditError) {
        let blocks = ChordProParser.parse(text).0.blocks
        switch blocks.first {
        case .blank, nil:
            guard chords == 0 else { throw .notLyricText(path) }
        case let .line(line):
            guard blocks.count == 1, line.segments.count(where: { $0.chord != nil }) == chords
            else { throw .notLyricText(path) }
        default:
            throw .notLyricText(path)
        }
    }

    static func validate(_ chord: String) throws(EditError) {
        let forbidden: Set<Character> = ["[", "]", "\n", "\r"]
        guard !chord.allSatisfy({ $0 == " " || $0 == "\t" }),
              !chord.contains(where: forbidden.contains)
        else { throw .invalidChordText(chord) }
    }

    static func firstWord(_ value: String?) -> String? {
        value?.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
    }
}

extension SourceSnapshot {
    /// Index of the last top-level directive in the leading run of directives and file
    /// comments, or `nil` when the song does not start with one.
    var leadingMetadataEnd: Int? {
        var last: Int?
        for (index, role) in map.roles.enumerated() {
            guard case let .block(path) = role, path.item == nil else { break }
            switch block(at: path) {
            case .directive: last = index
            case .fileComment: continue
            default: return last
            }
        }
        return last
    }

    /// Inserts `text` as a whole line after line `index` (at the top for `nil`), using the
    /// file's line ending.
    func insertLine(_ text: String, afterLine index: Int?, into builder: inout EditBuilder) {
        let ending = map.defaultEnding
        guard let index else {
            builder.insert(text + ending, at: 0)
            return
        }
        let line = map.lines[index]
        if line.hasEnding {
            builder.insert(text + line.ending, at: line.end)
        } else {
            builder.insert(ending + text, at: line.contentEnd)
        }
    }
}
