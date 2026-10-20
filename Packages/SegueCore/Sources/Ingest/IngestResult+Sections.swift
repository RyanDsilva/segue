import Foundation

/// Where each `{start_of_*}` section of `text` came from, in order (the review sheet marks
/// the ones a model labelled, spec 6.2). Mirrors `Converter.render`: a passthrough block
/// counts its own section directives, a content block one section per run (tab splits a
/// block), metadata and `other` blocks none.
public extension IngestResult {
    var sectionSources: [LabelSource] {
        guard !isAlreadyChordPro else { return [] }
        var sources: [LabelSource] = []
        for block in blocks {
            switch block.role {
            case .passthrough:
                let count = block.lines.count { line in
                    line.text.trimmingCharacters(in: .whitespaces)
                        .firstMatch(of: /(?i)^\{\s*(?:start_of_|so[cvbtg]\b)/) != nil
                }
                sources += Array(repeating: .notSection, count: count)
            case .metadata:
                continue
            case .content:
                guard block.label != .other else { continue }
                let body = block.lines.filter { $0.lineClass != .headerLine }
                let trailing = block.header?.trailingChords != nil
                guard !body.isEmpty || trailing else { continue }
                let runs = body.isEmpty ? 1 : Converter.runs(body).count
                sources += Array(repeating: block.labelSource, count: runs)
            }
        }
        return sources
    }
}
