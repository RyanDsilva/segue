import ChordPro
import MusicTheory

/// Turns any paste, `.txt` or `.crd` into ChordPro with no model (spec section 3):
/// Normalizer -> FormatDetector -> Segmenter + hints -> metadata -> Converter -> Validator ->
/// key inference. Pure and deterministic: the same text always gives the same result.
public enum IngestPipeline {
    public static func ingest(_ text: String, origin: IngestOrigin) -> IngestResult {
        var normalized = Normalizer.normalize(text)
        normalized.lines = ChordLines.bracketParenthesisedChords(normalized.lines)
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
        labelRepeats(&blocks)
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

    /// Whether `text` could be a song title or artist (not chords, a chord legend, a tuning,
    /// tab or a capo note). Model answers are checked with it too (P3-2).
    public static func isPlausibleName(_ text: String) -> Bool {
        MetadataExtractor.isPlausibleName(text)
    }

    // MARK: - Blocks

    private static func makeBlocks(_ lines: [IngestLine]) -> [IngestBlock] {
        Segmenter.groups(lines).enumerated().map { index, group in
            let header = group[0].lineClass == .headerLine ? HeaderParser.parse(group[0].text) : nil
            // A header whose name is not in the vocabulary (`[Harmonies]`) keeps its text as
            // the section label; its kind is left to the model.
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
            && (isChordLegend(blocks[index]) || isTempoWidget(blocks[index]))
        {
            let widget = isTempoWidget(blocks[index])
            setRole(.metadata, of: &blocks[index])
            if widget {
                blocks[index].lines[1].lineClass = .unknown
            }
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

    /// R101 plus P3-A's real-paste eval (docs/research/phase3-eval-real-pastes.md):
    ///
    /// 1. Repeats: an unheaded block whose lyrics repeat another block takes that block's
    ///    label when code knows it (a repeated intro stays an intro); when neither block is
    ///    named, both are choruses.
    /// 2. Continuation: an unheaded block with no repeat, chords-only or tab hint directly after
    ///    a lyric section its header named continues that section (a blank line inside a
    ///    section). Repeat-labelled blocks do not start a continuation: the next unheaded
    ///    block after a repeated chorus is usually a new verse.
    private static func labelRepeats(_ blocks: inout [IngestBlock]) {
        var partners: [Int: [Int]] = [:]
        for block in blocks where block.role == .content {
            if let earlier = block.hints.sameLyricsAs, blocks.indices.contains(earlier),
               blocks[earlier].role == .content
            {
                partners[block.index, default: []].append(earlier)
                partners[earlier, default: []].append(block.index)
            }
        }
        let known = blocks.map { $0.isUnlabelled ? nil : $0.label }
        let continued = continuations(blocks, partners: partners)
        for index in blocks.indices where blocks[index].isUnlabelled {
            guard let others = partners[index] else { continue }
            blocks[index].label = others.lazy.compactMap { known[$0] }.first ?? .chorus
            blocks[index].labelSource = .repetition
        }
        for index in blocks.indices where blocks[index].isUnlabelled {
            guard let label = continued[index] else { continue }
            blocks[index].label = label
            blocks[index].labelSource = .continuation
        }
    }

    /// The label each unheaded block would continue: the last header-named lyric section
    /// before it, through a run of unheaded blocks with no chords-only or tab hint. A block
    /// that repeats another ends the run after itself; a block with a header of its own (an
    /// unknown name such as `[Harmonies]`) is a new section and ends it.
    private static func continuations(
        _ blocks: [IngestBlock],
        partners: [Int: [Int]],
    ) -> [Int: SectionLabel] {
        var result: [Int: SectionLabel] = [:]
        var carry: SectionLabel?
        for block in blocks {
            let isLyricSection = block.role == .content && !block.hints.chordsOnly
                && !block.hints.guitarTab
            if isLyricSection, block.labelSource == .header, let label = block.label {
                carry = label
            } else if isLyricSection, block.isUnlabelled, block.header == nil, let label = carry {
                result[block.index] = label
                if partners[block.index] != nil {
                    carry = nil
                }
            } else {
                carry = nil
            }
        }
        return result
    }

    /// A chord site's strumming widget: a short label over a bare tempo (`Verse` / `88 bpm`,
    /// `Song` / `104 bpm`). Not a section, and its tempo is not the song's.
    private static func isTempoWidget(_ block: IngestBlock) -> Bool {
        guard block.lines.count == 2 else { return false }
        let label = block.lines[0].text.trimmingCharacters(in: .whitespaces)
        let tempo = block.lines[1].text.trimmingCharacters(in: .whitespaces)
        return label.split(separator: " ").count <= 3 && !label.contains(":")
            && tempo.wholeMatch(of: /(?i)\d{2,3}\s*bpm/) != nil
    }

    /// A block that is a header over chord-shape legend lines only (`[Coda]` then
    /// `G 3-5-5-4-3-3`) is a note, not a section.
    private static func isChordLegend(_ block: IngestBlock) -> Bool {
        let body = block.lines.filter { $0.lineClass != .headerLine }
        return !body.isEmpty && body.allSatisfy { ChordLines.isChordLegend($0.text) }
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
