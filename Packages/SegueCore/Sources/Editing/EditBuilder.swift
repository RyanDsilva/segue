// Owner: unit C (Editing). Collects raw replacements and normalises them into the minimal,
// ascending, non-overlapping `TextEdit`s a `SourceChange` promises.

struct EditBuilder {
    private let text: [UInt16]
    private var raw: [(order: Int, edit: TextEdit)] = []

    init(text: String) {
        self.text = Array(text.utf16)
    }

    mutating func replace(_ range: Range<Int>, with replacement: String) {
        raw.append((raw.count, TextEdit(range: range, replacement: replacement)))
    }

    mutating func insert(_ replacement: String, at offset: Int) {
        replace(offset ..< offset, with: replacement)
    }

    /// Sorted, merged where they touch or overlap, trimmed to what actually changes, and
    /// with no-op edits dropped.
    func edits() -> [TextEdit] {
        let sorted = raw.sorted {
            ($0.edit.range.lowerBound, $0.edit.range.upperBound, $0.order)
                < ($1.edit.range.lowerBound, $1.edit.range.upperBound, $1.order)
        }
        var merged: [TextEdit] = []
        for (_, edit) in sorted {
            guard var last = merged.last, edit.range.lowerBound <= last.range.upperBound else {
                merged.append(edit)
                continue
            }
            // Touching (or, defensively, overlapping): one edit over the union.
            last.replacement += edit.replacement
            last.range = last.range.lowerBound ..< max(last.range.upperBound, edit.range.upperBound)
            merged[merged.count - 1] = last
        }
        return merged.compactMap(trim)
    }

    /// Drops the common prefix and suffix (whole unicode scalars) of the replaced text and
    /// its replacement; `nil` if nothing changes.
    private func trim(_ edit: TextEdit) -> TextEdit? {
        let old = Array(String(decoding: text[edit.range], as: UTF16.self).unicodeScalars)
        let new = Array(edit.replacement.unicodeScalars)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
        {
            suffix += 1
        }
        if prefix == old.count, prefix == new.count {
            return nil
        }
        let units = { (scalars: ArraySlice<Unicode.Scalar>) in
            scalars.reduce(0) { $0 + UTF16.width($1) }
        }
        let lower = edit.range.lowerBound + units(old[..<prefix])
        let upper = edit.range.upperBound - units(old[(old.count - suffix)...])
        var replacement = String.UnicodeScalarView()
        replacement.append(contentsOf: new[prefix ..< (new.count - suffix)])
        return TextEdit(range: lower ..< upper, replacement: String(replacement))
    }
}
