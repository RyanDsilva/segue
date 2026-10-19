import ChordPro
import MusicTheory

/// Turns any paste, `.txt` or `.crd` into ChordPro with no model (spec section 3):
/// Normalizer -> FormatDetector -> Segmenter + hints -> metadata -> Converter -> Validator ->
/// key inference. Pure and deterministic: the same text always gives the same result.
public enum IngestPipeline {
    public static func ingest(_ text: String, origin: IngestOrigin) -> IngestResult {
        let normalized = Normalizer.normalize(text)
        let classes = FormatDetector.classify(normalized.lines)
        let format = FormatDetector.format(lines: normalized.lines, classes: classes)
        var lines = zip(normalized.lines, classes).enumerated().map { index, pair in
            let (text, lineClass) = pair
            let straight = [.headerLine, .metadata, .directive].contains(lineClass)
                ? Normalizer.straightenQuotes(text) : text
            return IngestLine(index: index, text: straight, lineClass: lineClass)
        }
        if format == .chordPro {
            return passthrough(text, origin: origin, lines: lines, removed: normalized.removed)
        }
        var blocks = makeBlocks(lines)
        Segmenter.computeHints(&blocks)
        for index in blocks.indices
            where blocks[index].header == nil && blocks[index].hints.guitarTab
        {
            blocks[index].label = .instrumental
            blocks[index].labelSource = .content
        }
        assignRoles(&blocks)
        let extraction = MetadataAssembly.extract(&blocks)
        for block in blocks {
            for line in block.lines {
                lines[line.index] = line
            }
        }
        let draft = IngestResult(
            origin: origin,
            format: format,
            isAlreadyChordPro: false,
            text: "",
            document: SongDocument(),
            lines: lines,
            blocks: blocks,
            metadata: extraction.metadata,
            keyInference: KeyInference(stated: nil, detection: nil),
            questions: RefinementQuestions(unheadedBlocks: [], unknownLines: []),
            diagnostics: [],
            directiveFields: extraction.directiveFields,
            consumedLines: extraction.consumedLines,
            removed: normalized.removed,
        )
        return assemble(draft)
    }

    /// Renders, parses and validates a draft (also the re-render step for refinements).
    static func assemble(_ draft: IngestResult) -> IngestResult {
        var result = draft
        let context = Converter.Context(
            headerDirectives: MetadataAssembly.directives(
                for: draft.metadata,
                skipping: draft.directiveFields,
            ),
            consumedLines: draft.consumedLines,
        )
        result.text = Converter.render(draft.blocks, context: context)
        let (document, parserDiagnostics) = ChordProParser.parse(result.text)
        result.document = document
        let report = Validator.validate(
            document,
            parserDiagnostics: parserDiagnostics,
            lines: draft.lines,
        )
        result.keyInference = KeyInference(stated: draft.metadata.key, chords: report.chords)
        result.questions = RefinementQuestions(
            unheadedBlocks: draft.blocks.filter(\.isUnlabelled).map(\.index),
            metadataCandidates: candidates(draft.blocks, chords: report.chords),
            unknownLines: draft.lines.filter { $0.lineClass == .unknown }.map(\.index),
        )
        result.diagnostics = draft.removed.map { .removedLine(text: $0.text, rule: $0.rule) }
            + draft.blocks.filter(\.isUnlabelled).map { .unlabelledBlock(index: $0.index) }
            + report.diagnostics
        return result
    }

    // MARK: - Blocks

    private static func makeBlocks(_ lines: [IngestLine]) -> [IngestBlock] {
        Segmenter.groups(lines).enumerated().map { index, group in
            let header = group[0].lineClass == .headerLine ? HeaderParser.parse(group[0].text) : nil
            let label = header?.label
            return IngestBlock(
                index: index,
                lines: group,
                header: header,
                role: .content,
                label: label,
                labelSource: label == nil ? .placeholder : .header,
                hints: BlockHints(),
            )
        }
    }

    /// Marks passthrough blocks (directives, explicit ChordPro sections) and metadata
    /// blocks (chord-free, unheaded text before the first or after the last song block).
    private static func assignRoles(_ blocks: inout [IngestBlock]) {
        for index in blocks.indices where isPassthrough(blocks[index]) {
            setRole(.passthrough, of: &blocks[index])
        }
        for index in blocks.indices where blocks[index].role == .content
            && blocks[index].lines.allSatisfy({ $0.lineClass == .metadata })
        {
            setRole(.metadata, of: &blocks[index])
        }
        let anchors = blocks.indices.filter { isAnchor(blocks[$0]) }
        if let first = anchors.first, let last = anchors.last {
            for index in blocks.indices where blocks[index].role == .content {
                let block = blocks[index]
                let isEdge = index < first || index > last && block.hints.sameLyricsAs == nil
                if isEdge, block.lines.count <= 6 {
                    setRole(.metadata, of: &blocks[index])
                }
            }
        } else if blocks.count > 1, blocks[0].role == .content,
                  MetadataAssembly.isTitleBlock(blocks[0])
        {
            setRole(.metadata, of: &blocks[0])
        }
    }

    private static func setRole(_ role: BlockRole, of block: inout IngestBlock) {
        block.role = role
        block.label = nil
        block.labelSource = .notSection
        guard role == .metadata else { return }
        for index in block.lines.indices where block.lines[index].lineClass == .lyricLine
            && !ChordLines.hasInlineChords(block.lines[index].text)
        {
            block.lines[index].lineClass = .unknown
            block.lines[index].text = Normalizer.straightenQuotes(block.lines[index].text)
        }
    }

    /// A block that is certainly song body: chords, a header or tab.
    private static func isAnchor(_ block: IngestBlock) -> Bool {
        block.role == .content && (Segmenter.hasChords(block) || block.header != nil
            || block.lines.contains { $0.lineClass == .tab })
    }

    private static func isPassthrough(_ block: IngestBlock) -> Bool {
        block.lines.contains { FormatDetector.isSectionDirective($0.text) }
            || block.lines.allSatisfy { line in
                line.lineClass == .directive
                    && FormatDetector.isDirective(line.text.trimmingCharacters(in: .whitespaces))
            }
    }

    // MARK: - Questions

    private static func candidates(
        _ blocks: [IngestBlock],
        chords: [ChartChord],
    ) -> MetadataCandidates? {
        let top = blocks.first.flatMap { $0.role == .metadata ? $0 : nil }
        let bottom = blocks.count > 1 ? blocks.last
            .flatMap { $0.role == .metadata ? $0 : nil } : nil
        let candidates = MetadataCandidates(
            topLines: top.map { Array($0.lines.prefix(8).map(\.text)) } ?? [],
            bottomLines: bottom.map { Array($0.lines.prefix(4).map(\.text)) } ?? [],
            chords: chords.map(\.original),
        )
        let isEmpty = candidates.topLines.isEmpty && candidates.bottomLines.isEmpty
            && candidates.chords.isEmpty
        return isEmpty ? nil : candidates
    }

    // MARK: - ChordPro passthrough

    private static func passthrough(
        _ text: String,
        origin: IngestOrigin,
        lines: [IngestLine],
        removed: [RemovedLine],
    ) -> IngestResult {
        let source = text.first == "\u{FEFF}" ? String(text.dropFirst()) : text
        let (document, parserDiagnostics) = ChordProParser.parse(source)
        let report = Validator.validate(document, parserDiagnostics: parserDiagnostics, lines: [])
        let blocks = Segmenter.groups(lines).enumerated().map { index, group in
            IngestBlock(
                index: index,
                lines: group,
                header: nil,
                role: .passthrough,
                label: nil,
                labelSource: .notSection,
                hints: BlockHints(),
            )
        }
        let meta = document.metadata
        return IngestResult(
            origin: origin,
            format: .chordPro,
            isAlreadyChordPro: true,
            text: source,
            document: document,
            lines: lines,
            blocks: blocks,
            metadata: IngestMetadata(
                title: meta.title,
                artists: meta.artists,
                key: meta.key,
                capo: meta.capo,
                tempo: meta.tempo.map { Int($0) },
            ),
            keyInference: KeyInference(stated: meta.key, chords: report.chords),
            questions: RefinementQuestions(unheadedBlocks: [], unknownLines: []),
            diagnostics: report.diagnostics,
            directiveFields: Set(MetadataKey.allCases),
            consumedLines: [],
            removed: removed,
        )
    }
}
