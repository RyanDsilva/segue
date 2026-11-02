import Foundation
import Ingest
import Plugins

/// Spec 8.5: every reader's result is checked before it is used; a failure falls back to the
/// generic reader (and a generic failure is `.noChart`), never to a half-parsed chart.
enum SanityCheck {
    enum Failure: String, Sendable, Hashable, CaseIterable {
        case fewLines
        case fewLyricLines
        case unreadableChords
        case junkLine
        case implausibleTitle
        case gluedChords
    }

    static let minimumLines = 4
    static let minimumLyricLines = 2
    static let minimumChordShare = 0.8
    static let maximumJunkShare = 0.2
    /// Bake-off 2.2: a contributed page with its chords glued into the words ("EmHum tere
    /// bin ab Creh nahi sakte") reads as lyrics with no chords; three such words reject it.
    static let maximumGluedWords = 3

    /// Words with a chord glued to their front ("EmHum", "DTere") or into their middle
    /// ("meCra", "waB7jood") on lyric lines.
    static func gluedWords(_ lines: [String], _ classes: [LineClass]) -> Int {
        zip(lines, classes).filter { $0.1 == .lyricLine }.reduce(0) { count, pair in
            count + pair.0.split(separator: " ").count { word in
                word.wholeMatch(of: /[A-G][#b]?(m|7|m7|maj7|sus[24]|add9|dim)?[A-Z][a-z].*/) != nil
                    || word.contains(/[a-z][A-G][#b]?(m|7|m7|maj7)?[a-z]/)
            }
        }
    }

    /// E-Chords: at least half the chords the page marked must stand on chord lines.
    static let minimumMarkedChordShare = 0.5

    /// A token that should be a chord (not a bar line, a repeat mark or a parenthesis).
    private static func isChordCandidate(_ token: Substring) -> Bool {
        token.contains(where: \.isLetter) && !token.hasPrefix("x") && !token.hasPrefix("(")
    }

    static func failures(_ chart: ParsedChart) -> [Failure] {
        let lines = chart.text.components(separatedBy: "\n")
        let classes = IngestPipeline.lineClasses(lines)
        var failures: [Failure] = []
        if lines.count(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) < minimumLines {
            failures.append(.fewLines)
        }
        if classes.count(where: { $0 == .lyricLine }) < minimumLyricLines {
            failures.append(.fewLyricLines)
        }
        var tokens: [String] = []
        for (line, lineClass) in zip(lines, classes) where lineClass == .chordLine {
            for token in line.split(whereSeparator: \.isWhitespace) where isChordCandidate(token) {
                tokens.append(String(token))
            }
        }
        let chords = tokens.count(where: IngestPipeline.isChordToken)
        if !tokens.isEmpty, Double(chords) < Double(tokens.count) * minimumChordShare {
            failures.append(.unreadableChords)
        }
        // Credit and note lines ("Tabbed by", "Thanks to") are junk the pipeline drops anyway;
        // a "chart" that is mostly site words is not a chart.
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if Double(nonBlank.count(where: IngestPipeline.isJunkLine)) > Double(nonBlank.count) *
            maximumJunkShare
        {
            failures.append(.junkLine)
        }
        if let title = chart.fields.title, !IngestPipeline.isPlausibleName(title) {
            failures.append(.implausibleTitle)
        }
        let marksLost = chart.chordMarks
            .map { $0 >= 4 && Double(chords) < Double($0) * minimumMarkedChordShare }
        if marksLost == true || gluedWords(lines, classes) >= maximumGluedWords {
            failures.append(.gluedChords)
        }
        return failures
    }
}

/// Spec 8.3: the reader by host (exact suffix match, no regex), its result checked, the
/// generic reader on the same HTML when it fails, `.noChart` when that fails too.
enum PageParserRegistry {
    static func reader(for url: URL) -> ReaderKind {
        let host = WebAddress.siteHost(url)
        if WebAddress.host(host, isWithin: "ultimate-guitar.com") {
            return .tabJSON
        }
        if WebAddress.host(host, isWithin: "e-chords.com") {
            return .chordPre
        }
        if WebAddress.host(host, isWithin: "chordie.com") {
            return .chordSpans
        }
        return .genericPage
    }

    /// Hosts that block plain requests outright, loaded through WebKit directly (8.3).
    static func loadsThroughWebKit(_ url: URL) -> Bool {
        reader(for: url) == .chordPre
    }

    /// The marker the hidden view waits for on this host's pages.
    static func marker(for url: URL) -> ReadyMarker {
        switch reader(for: url) {
        case .tabJSON: .tabStore
        case .chordPre: .chordPre
        default: .document
        }
    }

    static func read(
        _ text: String,
        url: URL,
        loadPath: LoadPath,
    ) -> Result<ImportedSong, ImportFailure> {
        let kind = reader(for: url)
        var fellBack = false
        if kind != .genericPage {
            switch site(kind, text, url) {
            case let .chart(chart) where SanityCheck.failures(chart).isEmpty:
                return .success(song(
                    chart,
                    url: url,
                    reader: kind,
                    fellBack: false,
                    loadPath: loadPath,
                ))
            case let .refused(reason):
                return .failure(.noChart(reason))
            case .chart, .unreadable:
                fellBack = true
            }
        }
        guard case let .chart(chart) = GenericPageReader.read(text, url: url),
              SanityCheck.failures(chart).isEmpty
        else { return .failure(.noChart(.notFound)) }
        return .success(song(
            chart,
            url: url,
            reader: .genericPage,
            fellBack: fellBack,
            loadPath: loadPath,
        ))
    }

    private static func site(_ kind: ReaderKind, _ text: String, _ url: URL) -> PageReading {
        switch kind {
        case .tabJSON: TabJSONParser.read(text, url: url)
        case .chordPre: ChordPreParser.read(text, url: url)
        case .chordSpans: ChordSpansParser.read(text, url: url)
        case .genericPage, .lyricsRecord: .unreadable
        }
    }

    private static func song(
        _ chart: ParsedChart,
        url: URL,
        reader: ReaderKind,
        fellBack: Bool,
        loadPath: LoadPath,
    ) -> ImportedSong {
        ImportedSong(text: chart.text, fields: chart.fields, provenance: Provenance(
            sourceURL: url,
            reader: reader,
            fellBack: fellBack,
            loadPath: loadPath,
            foundByContentSearch: chart.foundByContentSearch,
        ))
    }
}
