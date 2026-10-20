// Owner: P3-11 (section band). Plans the section operations as whole-line inserts,
// deletes and re-spellings of `{start_of_*}` / `{end_of_*}` lines only: every other byte of
// the song (lyrics, chords, comments, blanks) stays exactly as written.

import ChordPro
import Foundation

/// Where one top-level section sits in the source line table.
struct SectionSpan {
    let block: Int
    let section: Section
    /// Line index of `{start_of_...}`.
    let start: Int
    /// Line index of `{end_of_...}`; `nil` when the source never closed the section.
    let end: Int?
    /// Line indices of the section's items (may be empty).
    let items: Range<Int>

    var path: BlockPath {
        BlockPath(block: block)
    }

    /// The last line that belongs to the section (its end line, else its last item).
    var lastLine: Int {
        end ?? max(start, items.upperBound - 1)
    }
}

extension EditPlanner {
    mutating func wrapSection(
        first: BlockPath,
        last: BlockPath,
        kind: SectionKind,
        label: String?,
    ) throws(EditError) {
        guard first <= last else { throw .invalidPath(last) }
        for path in [first, last] {
            guard snapshot.block(at: path) != nil else { throw .invalidPath(path) }
            if path.item != nil {
                throw .crossesSection(BlockPath(block: path.block))
            }
        }
        for index in first.block ... last.block {
            if case .section = snapshot.document.blocks[index] {
                throw .crossesSection(BlockPath(block: index))
            }
        }
        let top = try lineIndex(first)
        let bottom = try lineIndex(last)
        snapshot.insertLine(
            DirectiveLine.sectionStart(kind, label: Self.cleanLabel(label)),
            afterLine: top == 0 ? nil : top - 1,
            into: &builder,
        )
        snapshot.insertLine(DirectiveLine.sectionEnd(kind), afterLine: bottom, into: &builder)
    }

    mutating func createSection(
        first: BlockPath,
        last: BlockPath,
        kind: SectionKind,
    ) throws(EditError) {
        guard first <= last, first.block < snapshot.document.blocks.count,
              last.block < snapshot.document.blocks.count
        else { throw .invalidPath(last) }
        let lyrics = snapshot.document.blocks[first.block ... last.block].compactMap { block in
            if case let .line(line) = block {
                line.segments.map(\.text).joined()
            } else {
                nil
            }
        }
        let proposal = SectionLabels.proposal(
            for: kind,
            lyrics: lyrics,
            at: first.block,
            in: snapshot.document,
        )
        try wrapSection(first: first, last: last, kind: kind, label: proposal.label)
        try apply(proposal.renames)
    }

    mutating func changeSectionKind(_ path: BlockPath, to kind: SectionKind) throws(EditError) {
        let span = try sectionSpan(path)
        guard !DirectiveLine.sameSectionKind(span.section.kind, kind) else { return }
        let lyrics = span.section.items.compactMap { item in
            if case let .line(line) = item {
                line.segments.map(\.text).joined()
            } else {
                nil
            }
        }
        let proposal = SectionLabels.proposal(
            for: kind,
            lyrics: lyrics,
            at: path.block,
            in: snapshot.document,
            excluding: path,
        )
        try setSectionKind(path, kind: kind, label: proposal.label)
        try apply(proposal.renames)
    }

    mutating func setSectionKind(
        _ path: BlockPath,
        kind: SectionKind,
        label: String?,
    ) throws(EditError) {
        let span = try sectionSpan(path)
        let label = Self.cleanLabel(label)
        if DirectiveLine.sameSectionKind(span.section.kind, kind) {
            try setSectionLabel(path, label: label)
            return
        }
        respell(span.start, as: DirectiveLine.sectionStart(kind, label: label))
        if let end = span.end {
            respell(end, as: DirectiveLine.sectionEnd(kind))
        }
    }

    mutating func moveSectionEdge(
        _ path: BlockPath,
        edge: SectionEdge,
        toLine target: BlockPath,
    ) throws(EditError) {
        let span = try sectionSpan(path)
        let line = try lineIndex(target)
        switch edge {
        case .top:
            moveTop(of: span, toLine: line)
        case .bottom:
            moveBottom(of: span, toLine: line)
        }
    }

    mutating func unwrapSection(_ path: BlockPath) throws(EditError) {
        let span = try sectionSpan(path)
        deleteLine(span.start)
        if let end = span.end {
            deleteLine(end)
        }
    }

    mutating func splitSection(_ path: BlockPath, atLine target: BlockPath) throws(EditError) {
        let span = try sectionSpan(path)
        guard target.block == path.block, let item = target.item,
              item > 0, item < span.section.items.count
        else { throw .invalidPath(target) }
        let line = snapshot.map.lines[span.items.lowerBound + item]
        let ending = snapshot.map.lines[span.start].hasEnding
            ? snapshot.map.lines[span.start].ending
            : snapshot.map.defaultEnding
        let end = span.end.map { snapshot.map.lines[$0].text }
            ?? DirectiveLine.sectionEnd(span.section.kind)
        // The second half is a new, distinct section of the same kind: numbered by the rule,
        // which may number the first half too ("Chorus" -> "Chorus 1" + "Chorus 2").
        let proposal = SectionLabels.proposal(
            for: span.section.kind,
            lyrics: nil,
            at: path.block,
            in: snapshot.document,
        )
        let start = DirectiveLine.sectionStart(span.section.kind, label: proposal.label)
        builder.insert(end + ending + start + ending, at: line.start)
        try apply(proposal.renames)
    }

    mutating func mergeSections(
        first: BlockPath,
        second: BlockPath,
        kind: SectionKind?,
    ) throws(EditError) {
        let upper = try sectionSpan(first)
        let lower = try sectionSpan(second)
        guard lower.block > upper.block else { throw .invalidPath(second) }
        for index in upper.block + 1 ..< lower.block {
            if case .section = snapshot.document.blocks[index] {
                throw .crossesSection(BlockPath(block: index))
            }
        }
        let same = DirectiveLine.sameSectionKind(upper.section.kind, lower.section.kind)
        guard kind != nil || same else { throw .sectionKindsDiffer(first, second) }
        let merged = kind ?? upper.section.kind
        if !DirectiveLine.sameSectionKind(upper.section.kind, merged) {
            respell(upper.start, as: DirectiveLine.sectionStart(merged, label: upper.section.label))
        }
        if let end = upper.end {
            deleteLine(end)
        }
        deleteLine(lower.start)
        if let end = lower.end, !DirectiveLine.sameSectionKind(lower.section.kind, merged) {
            respell(end, as: DirectiveLine.sectionEnd(merged))
        }
    }

    // MARK: - Edges

    /// The top edge moves so line `target` becomes the first line: up over the top-level
    /// lines above (never past the previous section or the leading metadata), or down over
    /// the section's own items (always keeping at least one).
    private mutating func moveTop(of span: SectionSpan, toLine target: Int) {
        var lowest = span.start
        let floor = (snapshot.leadingMetadataEnd ?? -1) + 1
        while lowest - 1 >= floor, isLooseLine(lowest - 1) {
            lowest -= 1
        }
        let highest = span.items.isEmpty ? span.start : span.items.upperBound - 1
        let line = min(max(target, lowest), highest)
        guard line != span.start, line != span.start + 1 else { return }
        let start = snapshot.map.lines[span.start]
        let ending = start.hasEnding ? start.ending : snapshot.map.defaultEnding
        deleteLine(span.start)
        builder.insert(start.text + ending, at: snapshot.map.lines[line].start)
    }

    /// The bottom edge moves so line `target` becomes the last line: down over the
    /// top-level lines below (never into the next section), or up over the section's own
    /// items (always keeping at least one). An unclosed section gets its end line here.
    private mutating func moveBottom(of span: SectionSpan, toLine target: Int) {
        let current = span.end.map { $0 - 1 } ?? span.lastLine
        var highest = current
        if let end = span.end {
            highest = end
            while highest + 1 < snapshot.map.lines.count, isLooseLine(highest + 1) {
                highest += 1
            }
        }
        let lowest = span.items.isEmpty ? span.start : span.items.lowerBound
        var line = min(max(target, lowest), highest)
        if line == span.end {
            line = current
        }
        guard line != current else { return }
        let text = span.end.map { snapshot.map.lines[$0].text }
            ?? DirectiveLine.sectionEnd(span.section.kind)
        if let end = span.end {
            deleteLine(end)
        }
        snapshot.insertLine(text, afterLine: line, into: &builder)
    }

    // MARK: - Helpers

    /// A source line that is a top-level block outside every section.
    private func isLooseLine(_ index: Int) -> Bool {
        guard index >= 0, index < snapshot.map.roles.count,
              case let .block(path) = snapshot.map.roles[index]
        else { return false }
        return path.item == nil
    }

    func sectionSpan(_ path: BlockPath) throws(EditError) -> SectionSpan {
        guard let top = snapshot.block(at: path) else { throw .invalidPath(path) }
        guard path.item == nil, case let .section(section) = top else {
            throw .wrongBlockKind(path)
        }
        let start = try lineIndex(path)
        let end = snapshot.map.roles.firstIndex(of: .sectionEnd(path.block))
        let items = start + 1 ..< start + 1 + section.items.count
        return SectionSpan(
            block: path.block,
            section: section,
            start: start,
            end: end,
            items: items,
        )
    }

    private func lineIndex(_ path: BlockPath) throws(EditError) -> Int {
        guard let index = snapshot.map.lineOfPath[path] else { throw .invalidPath(path) }
        return index
    }

    /// Relabels existing sections (numbering them), keeping each directive's spelling.
    private mutating func apply(_ renames: [BlockPath: String]) throws(EditError) {
        for (path, label) in renames.sorted(by: { $0.key < $1.key }) {
            try setSectionLabel(path, label: label)
        }
    }

    private mutating func respell(_ line: Int, as text: String) {
        builder.replace(snapshot.map.lines[line].contentRange, with: text)
    }

    private static func cleanLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
