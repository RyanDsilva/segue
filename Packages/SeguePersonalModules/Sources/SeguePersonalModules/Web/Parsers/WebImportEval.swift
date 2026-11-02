import Foundation
import Ingest
import Plugins

/// The offline eval's door into the readers (spec 16.3, `make eval-import`): one saved page
/// in, what the import would put in the review out. No network.
public enum WebImportEval {
    public struct Reading: Sendable {
        public var reader: ReaderKind?
        public var fellBack: Bool
        public var failure: ImportFailure?
        public var contentSearch: Bool
        /// The pipeline's result over the reader's text and fields, as the review opens it.
        public var result: IngestResult?
        /// The reader's own text, before the pipeline.
        public var text: String?
        /// Why the site reader's result was not used ("unreadable" or sanity failures).
        public var siteCheck: [String] = []
    }

    /// The site reader's own verdict, for diagnosing a fallback.
    public static func siteCheck(page html: String, url: URL) -> [String] {
        let reading: PageReading = switch PageParserRegistry.reader(for: url) {
        case .tabJSON: TabJSONParser.read(html, url: url)
        case .chordPre: ChordPreParser.read(html, url: url)
        case .chordSpans: ChordSpansParser.read(html, url: url)
        default: .unreadable
        }
        switch reading {
        case let .chart(chart):
            let junk = chart.text.components(separatedBy: "\n").filter(IngestPipeline.isJunkLine)
            return SanityCheck.failures(chart).map(\.rawValue) + junk.prefix(2)
                .map { "junk: \($0)" }
        case let .refused(reason): return ["refused \(reason.rawValue)"]
        case .unreadable:
            let store = TabJSONParser.store(in: html, url: url)
            let content = HTMLText.string(
                store,
                ["store", "page", "data", "tab_view", "wiki_tab", "content"],
            )
            guard let content, case let .failure(failure) = TabJSONParser.converted(content) else {
                return ["unreadable"]
            }
            return [
                "integrity \(failure.expected) vs \(failure.written): \(failure.line.prefix(90))",
            ]
        }
    }

    public static func read(page html: String, url: URL) -> Reading {
        switch PageParserRegistry.read(html, url: url, loadPath: .savedFile) {
        case let .failure(failure):
            return Reading(reader: nil, fellBack: false, failure: failure, contentSearch: false)
        case let .success(song):
            let result = IngestPipeline.ingest(song.text, origin: .web, source: song.fields)
            return Reading(
                reader: song.provenance.reader,
                fellBack: song.provenance.fellBack,
                failure: nil,
                contentSearch: song.provenance.foundByContentSearch,
                result: result,
                text: song.text,
            )
        }
    }

    /// The reader the registry picks for an address (canary output).
    public static func readerName(for url: URL) -> String {
        PageParserRegistry.reader(for: url).rawValue
    }
}
