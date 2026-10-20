import ChordPro
import Editing
import Foundation
import Ingest
import Library
import ModelPort
import Observation
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

    /// How long the refinement ran, once it finished (nil: no model was asked).
    var refinementSeconds: TimeInterval?
    let candidate: ImportCandidate?
    @ObservationIgnored var refinementTask: Task<Void, Never>?

    init(
        source: PasteSource,
        original: String,
        fileName: String? = nil,
        candidate: ImportCandidate? = nil,
        origin: IngestOrigin,
    ) {
        self.source = source
        self.original = original
        self.fileName = fileName
        self.candidate = candidate
        let result = IngestPipeline.ingest(original, origin: origin)
        base = result
        proposal = result
        text = result.text
        metadata = candidate?.metadata.map(SongMetadata.init) ?? SongMetadata()
        isRomanizedHindi = RomanizedHindi.isDetected(in: result)
        status = Self.needsRefinement(result) ? .queued : .notNeeded
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

    /// Whether Swap Title and Artist has anything to swap.
    public var canSwapTitleAndArtist: Bool {
        let metadata = SourceSnapshot(text: text).document.metadata
        let title = metadata.title?.trimmingCharacters(in: .whitespaces) ?? ""
        let artist = metadata.artists.first?.trimmingCharacters(in: .whitespaces) ?? ""
        return title != artist
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
