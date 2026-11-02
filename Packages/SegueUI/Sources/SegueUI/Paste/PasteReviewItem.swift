import ChordPro
import Editing
import Foundation
import Ingest
import Library
import ModelPort
import Observation
import Plugins
import Services

// One song in the paste review sheet (spec 6.2, R63): the deterministic result at once, AI
// refinements streamed in, edits by the user, nothing saved before Accept.

/// Where a refinement stands.
public enum PasteRefinementStatus: Equatable, Sendable {
    /// Waiting for its turn (a batch refines one file at a time, R94).
    case queued
    /// A model is running; `provider` is the first one the router will ask, if known.
    case running(ProviderKind?)
    /// Every task has answered or fallen through.
    case finished
    /// The user edited or accepted first, so refinement stopped (spec 6.2).
    case stopped
    /// Nothing to refine (already ChordPro, or no question for a model).
    case notNeeded
}

/// One pasted or converted song under review.
@MainActor
@Observable
public final class PasteReviewItem: Identifiable {
    public let id = UUID()
    public let source: PasteSource
    /// The text as pasted or read (the sheet's left side).
    public let original: String
    /// The file it came from (nil for a paste).
    public let fileName: String?
    /// The deterministic result (spec section 3).
    public let base: IngestResult
    /// The latest proposal: `base` with every AI answer so far merged in.
    public private(set) var proposal: IngestResult
    /// The ChordPro the song will be saved as (the sheet's right side; the draft card edits
    /// it too).
    public private(set) var text: String
    /// The draft card's tags and proficiency (sidecar fields).
    public var metadata: SongMetadata
    /// Ticked batch files import; unticked ones are listed as not imported (R96).
    public var isTicked = true
    public private(set) var status: PasteRefinementStatus
    /// How each task routed (footer and analytics).
    public private(set) var reports: [ModelTaskKind: RoutingReport] = [:]
    /// The user changed the text or the card.
    public private(set) var isEdited = false
    /// The romanized-Hindi detection fired (R98).
    public let isRomanizedHindi: Bool

    /// The library song this one looks like (title, artist and content, R154), or the one
    /// with exactly its bytes (`isAlreadyInLibrary`); nil when neither. Shown beside the
    /// card, never blocking Accept; re-checked whenever the text changes.
    public private(set) var nearDuplicate: NearDuplicateIndex.Match?
    /// `nearDuplicate` has exactly this song's bytes (a byte-identical paste, R158 Q9).
    public private(set) var isAlreadyInLibrary = false
    /// The library to check against (set by the review when it opens).
    @ObservationIgnored var nearDuplicates: NearDuplicateIndex? {
        didSet { refreshNearDuplicate() }
    }

    /// Where a web page or search result came from (P9-4 spec 11.6): the review header's
    /// source line. Never stored (R179). Nil for pastes and files.
    public let provenance: Provenance?
    /// R194: the source's film song name had more than one " - " and no model picked the
    /// split, so the title and Movie / Album are flagged for review.
    public let titleUncertain: Bool

    /// How long the refinement ran, once it finished (nil: no model was asked).
    var refinementSeconds: TimeInterval?
    let candidate: ImportCandidate?
    @ObservationIgnored var refinementTask: Task<Void, Never>?

    convenience init(
        source: PasteSource,
        original: String,
        fileName: String? = nil,
        candidate: ImportCandidate? = nil,
        origin: IngestOrigin,
    ) {
        self.init(
            source: source,
            original: original,
            fileName: fileName,
            candidate: candidate,
            result: IngestPipeline.ingest(original, origin: origin),
        )
    }

    /// A web page or search result (P9-4 spec 5.2): the source's fields win over the text.
    convenience init(song: ImportedSong, source: PasteSource) {
        let origin: IngestOrigin = song.provenance.reader == .lyricsRecord ? .lyrics : .web
        self.init(
            source: source,
            original: song.text,
            result: IngestPipeline.ingest(song.text, origin: origin, source: song.fields),
            provenance: song.provenance,
            titleUncertain: song.fields.titleUncertain,
        )
    }

    private init(
        source: PasteSource,
        original: String,
        fileName: String? = nil,
        candidate: ImportCandidate? = nil,
        result: IngestResult,
        provenance: Provenance? = nil,
        titleUncertain: Bool = false,
    ) {
        self.source = source
        self.original = original
        self.fileName = fileName
        self.candidate = candidate
        self.provenance = provenance
        self.titleUncertain = titleUncertain
        base = result
        proposal = result
        // An already-ChordPro lookalike is kept exactly as read: no model runs and Accept
        // writes its bytes unchanged (R158 Q4).
        text = source == .fileCho ? original : result.text
        metadata = candidate?.metadata.map(SongMetadata.init) ?? SongMetadata()
        isRomanizedHindi = RomanizedHindi.isDetected(in: result)
        status = source != .fileCho && Self.needsRefinement(result) ? .queued : .notNeeded
    }

    /// The callout beside the card, or nil.
    public var nearDuplicateText: String? {
        guard let match = nearDuplicate else { return nil }
        if isAlreadyInLibrary {
            return "Already in your library as “\(match.title)”."
        }
        let artist = match.artist.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return artist.isEmpty ? "Looks like “\(match.title)” in your library."
            : "Looks like “\(match.title)” by \(artist) in your library."
    }

    /// Re-checks the text as it is now against the library.
    private func refreshNearDuplicate() {
        guard let index = nearDuplicates else {
            nearDuplicate = nil
            isAlreadyInLibrary = false
            return
        }
        let hash = NearDuplicateIndex.contentHash(of: text)
        if let identical = index.identical(contentHash: hash) {
            nearDuplicate = identical
            isAlreadyInLibrary = true
            return
        }
        let document = SourceSnapshot(text: text).document
        isAlreadyInLibrary = false
        nearDuplicate = index.match(
            title: document.metadata.title,
            artists: document.metadata.artists,
            lyrics: document.plainLyrics,
            contentHash: hash,
        )
    }

    /// Whether any model question exists for `result`.
    static func needsRefinement(_ result: IngestResult) -> Bool {
        PasteRefiner.labelTask(for: result) != nil || PasteRefiner.metadataTask(for: result) != nil
            || PasteRefiner.ambiguousLineTask(for: result) != nil
    }

    // MARK: Editing

    /// The user's edit of the ChordPro text (the text view or the draft card): refinement
    /// stops so it never overwrites what the user typed.
    public func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        isEdited = true
        stopRefinement()
        refreshNearDuplicate()
    }

    /// Swaps `{title}` and `{artist}` (some sites write "Artist - Title"; the converter keeps
    /// "Title - Artist", P3-2 Q3). One edit.
    public func swapTitleAndArtist() {
        let snapshot = SourceSnapshot(text: text)
        let metadata = snapshot.document.metadata
        let title = metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        let artist = metadata.artists.first?.trimmingCharacters(in: .whitespaces) ?? ""
        guard title != artist else { return }
        var swapped = text
        for operation in [
            EditOperation.setDirective(name: "title", value: artist.isEmpty ? nil : artist),
            .setDirective(name: "artist", value: title.isEmpty ? nil : title),
        ] {
            let current = SourceSnapshot(text: swapped)
            guard let change = try? DocumentEditor.change(for: operation, in: current) else {
                return
            }
            swapped = swapped.applying(change.edits)
        }
        edit(swapped)
    }

    /// Whether Swap Title and Artist has anything to swap: one artist at most (P8-8 section
    /// 3.6; with two or more, which one would be the title?).
    public var canSwapTitleAndArtist: Bool {
        let metadata = SourceSnapshot(text: text).document.metadata
        guard metadata.artists.count <= 1 else { return false }
        let title = metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        let artist = metadata.artists.first?.trimmingCharacters(in: .whitespaces) ?? ""
        return title != artist
    }

    /// Why Swap is off, for its help.
    public var swapHelp: String {
        SourceSnapshot(text: text).document.metadata.artists.count > 1
            ? "Swap works with one artist" : "Some sites write “Artist - Title”"
    }

    // MARK: Artist splits (P8-8 section 3.7)

    /// The splits the converter made that still stand in the text: every part present, in
    /// order and next to each other. A hand edit of those chips ends the line.
    public var standingSplits: [ArtistSplit] {
        let artists = SourceSnapshot(text: text).document.metadata.artists
        return base.artistSplits.filter { Self.range(of: $0.parts, in: artists) != nil }
    }

    /// Keep as one: the split's parts become the original value again, in place (one edit
    /// of the review text, one undo step).
    public func keepAsOne(_ split: ArtistSplit) {
        let artists = SourceSnapshot(text: text).document.metadata.artists
        guard let range = Self.range(of: split.parts, in: artists) else { return }
        var merged = artists
        merged.replaceSubrange(range, with: [split.original])
        let snapshot = SourceSnapshot(text: text)
        guard let change = try? DocumentEditor.change(for: .setArtists(merged), in: snapshot)
        else { return }
        mergedSplits.insert(split.original)
        edit(text.applying(change.edits))
    }

    /// Originals merged back with Keep as one (row 29's `merged`).
    private(set) var mergedSplits: Set<String> = []

    /// Row 29 for each split at Accept: merged with Keep as one, kept as split, or edited.
    var splitOutcomes: [(ArtistSplit, ArtistSplitOutcome)] {
        let standing = standingSplits
        return base.artistSplits.map { split in
            if mergedSplits.contains(split.original) {
                (split, .merged)
            } else if standing.contains(split) {
                (split, .kept)
            } else {
                (split, .edited)
            }
        }
    }

    /// Where `parts` sit, contiguous and in order, in `artists`.
    static func range(of parts: [String], in artists: [String]) -> Range<Int>? {
        guard !parts.isEmpty, parts.count <= artists.count else { return nil }
        for start in 0 ... artists.count - parts.count
            where Array(artists[start ..< start + parts.count]) == parts
        {
            return start ..< start + parts.count
        }
        return nil
    }

    // MARK: AI marks

    /// Blocks whose label a model decided (marked apart from rule-based conversion).
    public var aiLabelledBlocks: [Int] {
        proposal.blocks.filter { $0.labelSource == .refined }.map(\.index)
    }

    /// Title and artist fields a model filled in.
    public var aiFields: Set<RefinedField> {
        proposal.refinedFields
    }

    /// Whether anything in the proposal came from a model.
    public var hasAIDecisions: Bool {
        !aiLabelledBlocks.isEmpty || !aiFields.isEmpty
    }

    /// The sections of `document` (the text as it is now) a model labelled, by their order
    /// among the `{start_of_*}` sections. Empty when an edit changed the section count.
    func aiSectionOrdinals(in document: SongDocument) -> Set<Int> {
        let sources = proposal.sectionSources
        let sections = document.blocks.count { block in
            if case .section = block {
                return true
            }
            return false
        }
        guard sections == sources.count else { return [] }
        return Set(sources.indices.filter { sources[$0] == .refined })
    }

    /// Junk lines the converter dropped (struck through on the original side).
    public var removedLines: Set<String> {
        Set(base.diagnostics.compactMap { diagnostic in
            if case let .removedLine(text, _) = diagnostic {
                return text.trimmingCharacters(in: .whitespaces)
            }
            return nil
        })
    }

    /// Lines code could not place, kept as notes (R101; flagged on both sides).
    public var unknownLines: Set<String> {
        Set(proposal.lines.filter { $0.lineClass == .unknown }
            .map { $0.text.trimmingCharacters(in: .whitespaces) })
    }

    /// Chord tokens that do not parse (flagged in the footer).
    public var badChords: [String] {
        proposal.diagnostics.compactMap { diagnostic in
            if case let .unparseableChord(token, _) = diagnostic {
                return token
            }
            return nil
        }
    }

    /// The key heard in the chords, offered as a suggestion only (R101).
    public var suggestedKey: String? {
        let inference = proposal.keyInference
        guard inference.stated == nil else { return nil }
        return (inference.refined ?? inference.detection?.key)?.name
    }

    // MARK: Refinement

    /// Takes one streamed update (ignored once the user edited).
    func apply(_ update: PasteRefinementUpdate) {
        reports = update.reports
        guard !isEdited, status != .stopped else { return }
        proposal = update.result
        text = update.result.text
        refreshNearDuplicate()
    }

    func refinementStarted(_ provider: ProviderKind?) {
        status = .running(provider)
    }

    func refinementFinished(seconds: TimeInterval?) {
        refinementTask = nil
        refinementSeconds = seconds
        if status != .stopped {
            status = .finished
        }
    }

    /// Stops a running or queued refinement (edit, Accept, Cancel, untick).
    func stopRefinement() {
        refinementTask?.cancel()
        refinementTask = nil
        switch status {
        case .queued, .running:
            status = .stopped
        case .finished, .notNeeded, .stopped:
            break
        }
    }

    /// The candidate Accept writes.
    var importCandidate: ImportCandidate {
        let stand = candidate ?? ImportCandidate.paste(text: text)
        return stand.reviewed(text: text, metadata: metadata)
    }
}
