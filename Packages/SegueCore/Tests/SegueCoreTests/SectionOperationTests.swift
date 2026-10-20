import ChordPro
import Editing
import Foundation
import Testing

/// P3-11 step 1: the section operations over real documents (the shipped Welcome songs,
/// the paste goldens and the editing corpus). Every operation is one `SourceChange` (one
/// undo step), touches only `{start_of_*}` / `{end_of_*}` lines, keeps every lyric, chord
/// and comment byte for byte, and round-trips through the parser and serializer.
struct SectionOperationTests {
    // MARK: - Documents

    static let welcomeFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "SegueUI/Sources/SegueUI/App/WelcomeLibrary", directoryHint: .isDirectory)

    static let welcome = [
        "soundcheck-at-seven.cho", "kitaabon-wali-gali.cho", "kettle-on-lights-low.cho",
        "ferry-lights-over-calder-bay.cho",
    ]

    /// Welcome songs, paste goldens and the well-formed editing fixtures.
    static let documents: [String] = welcome.map { "welcome/\($0)" }
        + pasteGoldens.map { "paste/\($0)" } + EditingFixtures.wellFormed

    static let pasteGoldens: [String] = {
        guard let directory = Bundle.module.url(forResource: "Fixtures/paste", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return files.filter { $0.hasSuffix(".cho") }.sorted()
    }()

    static func load(_ name: String) throws -> String {
        if name.hasPrefix("welcome/") {
            let url = welcomeFolder.appending(path: String(name.dropFirst("welcome/".count)))
            return try String(contentsOf: url, encoding: .utf8)
        }
        return try EditingFixtures.load(name)
    }

    static func kitaabon() throws -> SourceSnapshot {
        try SourceSnapshot(text: load("welcome/kitaabon-wali-gali.cho"))
    }

    // MARK: - Corpus properties

    @Test
    func `the corpus has real documents with sections`() throws {
        #expect(Self.pasteGoldens.count >= 20)
        let sections = try Self.documents.reduce(0) { total, name in
            try total + SourceSnapshot(text: Self.load(name)).sectionPaths.count
        }
        #expect(sections > 100)
    }

    @Test(arguments: documents)
    func `unwrapping then wrapping every section keeps every content line`(name: String) throws {
        let snapshot = try SourceSnapshot(text: Self.load(name))
        for path in snapshot.lyricSectionPaths {
            let section = try #require(snapshot.section(at: path))
            let unwrap = try DocumentEditor.change(for: .unwrapSection(path), in: snapshot)
            #expect(unwrap.actionName == "Remove Section")
            let open = try expectSectionEdit(unwrap, in: snapshot)
            #expect(open.sectionPaths.count == snapshot.sectionPaths.count - 1)
            guard !section.items.isEmpty else { continue }
            // The section's items are now top-level blocks starting at its old index.
            let first = BlockPath(block: path.block)
            let last = BlockPath(block: path.block + section.items.count - 1)
            let wrap = try DocumentEditor.change(
                for: .wrapSection(
                    first: first,
                    last: last,
                    kind: section.kind,
                    label: section.label,
                ),
                in: open,
            )
            #expect(wrap.actionName == "New Section")
            let closed = try expectSectionEdit(wrap, in: open)
            let again = try #require(closed.section(at: path))
            #expect(again.items == section.items)
            #expect(again.label == section.label.flatMap { $0.isEmpty ? nil : $0 })
            #expect(DirectiveLine.sameSectionKind(again.kind, section.kind))
        }
    }

    @Test(arguments: documents)
    func `splitting every section anywhere and merging it back restores the text`(
        name: String,
    ) throws {
        let snapshot = try SourceSnapshot(text: Self.load(name))
        for path in snapshot.lyricSectionPaths {
            let section = try #require(snapshot.section(at: path))
            for item in 1 ..< max(1, section.items.count) {
                let split = try DocumentEditor.change(
                    for: .splitSection(path, atLine: BlockPath(block: path.block, item: item)),
                    in: snapshot,
                )
                let halves = try expectSectionEdit(split, in: snapshot)
                let head = try #require(halves.section(at: path))
                let tail = try #require(halves.section(at: BlockPath(block: path.block + 1)))
                #expect(head.items.count == item)
                #expect(tail.items.count == section.items.count - item)
                let merge = try DocumentEditor.change(
                    for: .mergeSections(
                        first: path,
                        second: BlockPath(block: path.block + 1),
                        kind: nil,
                    ),
                    in: halves,
                )
                let merged = try expectSectionEdit(merge, in: halves)
                #expect(merged.text == snapshot.text)
            }
        }
    }

    @Test(arguments: documents)
    func `changing every section's kind re-spells only its directives`(name: String) throws {
        let snapshot = try SourceSnapshot(text: Self.load(name))
        for path in snapshot.lyricSectionPaths {
            let section = try #require(snapshot.section(at: path))
            for kind in [SectionKind.chorus, .bridge, .custom("intro")] {
                let change = try DocumentEditor.change(
                    for: .setSectionKind(path, kind: kind, label: "Part 9"),
                    in: snapshot,
                )
                let after = try expectSectionEdit(change, in: snapshot)
                let changed = try #require(after.section(at: path))
                #expect(DirectiveLine.sameSectionKind(changed.kind, kind))
                #expect(changed.label == "Part 9")
                #expect(changed.items == section.items)
            }
        }
    }

    @Test(arguments: documents)
    func `moving every edge to its neighbours keeps content`(name: String) throws {
        let snapshot = try SourceSnapshot(text: Self.load(name))
        for path in snapshot.lyricSectionPaths {
            for edge in [SectionEdge.top, .bottom] {
                for target in snapshot.edgeTargets(around: path) {
                    let change = try DocumentEditor.change(
                        for: .moveSectionEdge(path, edge: edge, toLine: target),
                        in: snapshot,
                    )
                    let after = try expectSectionEdit(change, in: snapshot)
                    #expect(after.sectionPaths.count == snapshot.sectionPaths.count)
                }
            }
        }
    }

    // MARK: - Kitaabon Wali Gali, exact results

    @Test
    func `wrapping four loose lines makes a numbered chorus around exactly them`() throws {
        let original = try Self.kitaabon()
        let verse2 = try BlockPath(block: #require(original.sectionPaths.dropFirst(2).first).block)
        let loose = try expectSectionEdit(
            DocumentEditor.change(for: .unwrapSection(verse2), in: original),
            in: original,
        )
        let label = SectionLabels.next(for: .chorus, in: loose.document)
        #expect(label == "Chorus 2")
        let change = try DocumentEditor.change(
            for: .wrapSection(
                first: BlockPath(block: verse2.block),
                last: BlockPath(block: verse2.block + 3),
                kind: .chorus,
                label: label,
            ),
            in: loose,
        )
        let after = try expectSectionEdit(change, in: loose)
        #expect(after.text.contains("""
        {start_of_chorus: Chorus 2}
        [Am]Baarish ki boondein [G]khidki pe likhti,
        [F]Adhoori si kavita [E]jo tujh tak pahunchti,
        [Am]Raaste wahi hain, [G]mausam naya,
        [F]Dil ne phir se [E]wahi geet gaaya.
        {end_of_chorus}
        """))
        #expect(after.parseDiagnostics.isEmpty)
    }

    @Test
    func `a wrap that crosses or sits inside a section is refused`() throws {
        let snapshot = try Self.kitaabon()
        let verse1 = try #require(snapshot.sectionPaths.first)
        // From the comment line above Verse 1 into it.
        let comment = BlockPath(block: verse1.block - 2)
        #expect(throws: EditError.crossesSection(verse1)) {
            try DocumentEditor.change(
                for: .wrapSection(first: comment, last: verse1, kind: .verse, label: nil),
                in: snapshot,
            )
        }
        let inside = BlockPath(block: verse1.block, item: 1)
        #expect(throws: EditError.crossesSection(verse1)) {
            try DocumentEditor.change(
                for: .wrapSection(first: inside, last: inside, kind: .chorus, label: nil),
                in: snapshot,
            )
        }
    }

    @Test
    func `merging different kinds asks for the kind, then uses it`() throws {
        let snapshot = try Self.kitaabon()
        let verse1 = snapshot.sectionPaths[0]
        let chorus = snapshot.sectionPaths[1]
        #expect(throws: EditError.sectionKindsDiffer(verse1, chorus)) {
            try DocumentEditor.change(
                for: .mergeSections(first: verse1, second: chorus, kind: nil),
                in: snapshot,
            )
        }
        let change = try DocumentEditor.change(
            for: .mergeSections(first: verse1, second: chorus, kind: .chorus),
            in: snapshot,
        )
        let after = try expectSectionEdit(change, in: snapshot)
        let merged = try #require(after.section(at: verse1))
        #expect(merged.kind == .chorus)
        #expect(merged.label == "Verse 1")
        #expect(merged.items.count(where: {
            if case .line = $0 {
                true
            } else {
                false
            }
        }) == 8)
        #expect(after.parseDiagnostics.isEmpty)
    }

    @Test
    func `labels number from the sections already in the song`() throws {
        let document = try Self.kitaabon().document
        #expect(SectionLabels.next(for: .verse, in: document) == "Verse 3")
        #expect(SectionLabels.next(for: .chorus, in: document) == "Chorus 2")
        #expect(SectionLabels.next(for: .bridge, in: document) == "Bridge 2")
        #expect(SectionLabels.next(for: .custom("intro"), in: document) == "Intro 1")
        let gaps = SourceSnapshot(text: "{sov: Verse 4}\na\n{eov}\n{sov}\nb\n{eov}\n").document
        #expect(SectionLabels.next(for: .verse, in: gaps) == "Verse 5")
        #expect(SectionLabels.displayName(.custom("pre_chorus")) == "Pre Chorus")
    }

    // MARK: - Edge clamping (unit)

    @Test
    func `edges clamp at the leading metadata and the neighbouring sections`() throws {
        let text = """
        {title: T}
        {key: G}

        loose a
        {start_of_verse: Verse 1}
        v1
        v2
        {end_of_verse}
        loose b

        {start_of_chorus}
        c1
        {end_of_chorus}
        loose c
        """
        let snapshot = SourceSnapshot(text: text)
        let verse = snapshot.sectionPaths[0]
        let chorus = snapshot.sectionPaths[1]
        func move(_ path: BlockPath, _ edge: SectionEdge, _ target: BlockPath) throws -> String {
            try snapshot.text.applying(DocumentEditor.change(
                for: .moveSectionEdge(path, edge: edge, toLine: target),
                in: snapshot,
            ).edits)
        }
        // Top up to {title}: stops below the metadata, on the blank line.
        #expect(try move(verse, .top, BlockPath(block: 0)).hasPrefix(
            "{title: T}\n{key: G}\n{start_of_verse: Verse 1}\n\nloose a\nv1",
        ))
        // Top down past the last item: keeps one line.
        #expect(try move(verse, .top, chorus).contains("v1\n{start_of_verse: Verse 1}\nv2\n"))
        // Bottom down into the chorus: stops on the blank line before it.
        #expect(try move(verse, .bottom, chorus).contains("v2\nloose b\n\n{end_of_verse}\n"))
        // Bottom up to its first line.
        #expect(try move(verse, .bottom, BlockPath(block: verse.block, item: 0))
            .contains("v1\n{end_of_verse}\nv2\nloose b"))
        // Chorus top up: stops after the verse's end line; bottom down to the last line.
        #expect(try move(chorus, .top, verse)
            .contains("{end_of_verse}\n{start_of_chorus}\nloose b"))
        #expect(try move(chorus, .bottom, BlockPath(block: chorus.block + 1))
            .hasSuffix("c1\nloose c\n{end_of_chorus}"))
        // Onto its own lines: no change.
        #expect(try DocumentEditor.change(
            for: .moveSectionEdge(
                verse,
                edge: .bottom,
                toLine: BlockPath(block: verse.block, item: 1),
            ),
            in: snapshot,
        ).isEmpty)
    }
}

// MARK: - Helpers

extension SourceSnapshot {
    var sectionPaths: [BlockPath] {
        document.blocks.indices.compactMap { index in
            if case .section = document.blocks[index] {
                BlockPath(block: index)
            } else {
                nil
            }
        }
    }

    /// Sections whose body is lyrics (tab and grid bodies are verbatim text: moving lines
    /// in or out of them changes what counts as a lyric, so the corpus checks skip them).
    var lyricSectionPaths: [BlockPath] {
        sectionPaths.filter { path in
            section(at: path).map { !DirectiveLine.isVerbatimSection($0.kind) } ?? false
        }
    }

    /// Edge targets around a section: the blocks either side, its first, second and last
    /// items, and the first and last blocks of the song.
    func edgeTargets(around path: BlockPath) -> [BlockPath] {
        let count = section(at: path)?.items.count ?? 0
        let candidates = [
            BlockPath(block: 0), BlockPath(block: max(0, path.block - 1)), path,
            BlockPath(block: path.block, item: 0), BlockPath(block: path.block, item: 1),
            BlockPath(block: path.block, item: max(0, count - 1)),
            BlockPath(block: path.block + 1), BlockPath(block: document.blocks.count - 1),
        ]
        return candidates.filter { allPaths.contains($0) }
    }

    /// Every block path in source order (section headers and their items included).
    var allPaths: [BlockPath] {
        document.blocks.indices.flatMap { index -> [BlockPath] in
            guard case let .section(section) = document.blocks[index] else {
                return [BlockPath(block: index)]
            }
            return [BlockPath(block: index)]
                + section.items.indices.map { BlockPath(block: index, item: $0) }
        }
    }

    func section(at path: BlockPath) -> Section? {
        guard document.blocks.indices.contains(path.block),
              case let .section(section) = document.blocks[path.block]
        else { return nil }
        return section
    }
}

/// Source lines that are not section start/end directives: lyrics, chords, comments,
/// metadata and blanks, exactly as written.
private func contentLines(_ text: String) -> [String] {
    // Every line ending counts (`\n`, `\r\n` and a lone `\r`).
    text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        .filter { line in
            guard let directive = DirectiveLine(line) else { return true }
            return !directive.name.hasPrefix("start_of_") && !directive.name.hasPrefix("end_of_")
        }
}

/// The change is well formed, keeps every content line (zero lyric and chord change) and
/// introduces no new parse diagnostic; returns the snapshot after it.
@discardableResult
private func expectSectionEdit(
    _ change: SourceChange,
    in snapshot: SourceSnapshot,
) throws -> SourceSnapshot {
    try expectWellFormed(change, in: snapshot)
    let after = snapshot.applying(change)
    #expect(contentLines(after.text) == contentLines(snapshot.text))
    #expect(after.chords.map(\.token.original) == snapshot.chords.map(\.token.original))
    #expect(after.document.plainLyrics == snapshot.document.plainLyrics)
    #expect(after.parseDiagnostics.count <= snapshot.parseDiagnostics.count)
    return after
}
