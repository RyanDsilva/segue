import Foundation
import Ingest
import Library
import ModelPort
import Observation
import Plugins
import Services

// The paste review sheet's state (spec 6.1-6.2, R83, R93-R96): the New Song input state,
// one pasted song, or a batch of converted files. Look-independent: the views render it.

/// What the sheet shows.
public enum PasteReviewPhase: Equatable, Sendable {
    /// New Song (R83): "Paste or type a song"; the clipboard is never read before Command-V.
    case input
    /// One song or a batch of files under review.
    case review
    /// Find Lyrics (P9-4 spec 6.4, Personal build only): the plugin's search; a picked
    /// result moves the same sheet to review.
    case search
}

/// The review sheet's model. Opens with deterministic results at once; refinement runs in
/// the background, one song at a time (one model load per song, R94), and never blocks the
/// sheet. Nothing is written before Accept.
@MainActor
@Observable
public final class PasteReviewModel {
    public private(set) var phase: PasteReviewPhase
    public private(set) var items: [PasteReviewItem]
    public var selectedID: PasteReviewItem.ID?
    /// The text typed in the input state.
    public var draftText = ""
    /// True once Accept or Cancel ran (the host dismisses the sheet).
    public private(set) var isClosed = false
    /// P9-4 spec 11.4-11.5: an address or saved page the web field reads as soon as it
    /// appears (a lone pasted URL, a dropped link, Import a Saved Page).
    public private(set) var pendingWebInput: PendingWebInput?
    /// The web field is reading a page: the text area dims (spec 11.3).
    public var isReadingWeb = false
    /// Paste the Page Instead (spec 8.6): the input state explains copying the page.
    public private(set) var showsPasteHint = false
    /// The Personal build's web import exists (the lone-URL rule of spec 11.4).
    public let webImportAvailable: Bool
    /// Import from Web Page opened the sheet: the web field has focus (spec 11.1).
    public var focusesWebField = false

    /// How the files came in (nil for a paste): the import analytics row.
    public let importMethod: ImportMethod?
    /// Files of the same import that are already ChordPro (A29): written with the reviewed
    /// ones as ONE import (one undo step), also on Cancel.
    public let directFiles: [ImportCandidate]
    /// Files the import left out before review (not songs, duplicates, during a show).
    public let preSkipped: [ImportSkip]

    /// The library the songs are checked against for lookalikes (R154).
    @ObservationIgnored let nearDuplicates: NearDuplicateIndex?
    @ObservationIgnored private let router: Router
    @ObservationIgnored private let services: ServicesHub
    @ObservationIgnored private let commit: ([ImportCandidate]) async -> ImportSummary?
    @ObservationIgnored private var queue: Task<Void, Never>?

    /// - Parameters:
    ///   - items: the songs to review (empty for the New Song input state).
    ///   - importMethod: how the files came in (nil for a paste).
    ///   - directFiles: already-ChordPro files of the same import.
    ///   - preSkipped: files the import left out before review.
    ///   - nearDuplicates: the library the songs are checked against for lookalikes.
    ///   - router: the AI router (`AIServices.router`).
    ///   - services: the analytics hub.
    ///   - search: opens on Find Lyrics instead of the input state.
    ///   - webImport: the Personal build's web import exists.
    ///   - commit: writes the accepted songs as one import; nil when it failed.
    init(
        items: [PasteReviewItem],
        importMethod: ImportMethod? = nil,
        directFiles: [ImportCandidate] = [],
        preSkipped: [ImportSkip] = [],
        nearDuplicates: NearDuplicateIndex? = nil,
        router: Router,
        services: ServicesHub,
        search: Bool = false,
        webImport: Bool = false,
        commit: @escaping ([ImportCandidate]) async -> ImportSummary?,
    ) {
        phase = items.isEmpty ? (search ? .search : .input) : .review
        webImportAvailable = webImport
        self.items = items
        selectedID = items.first?.id
        self.importMethod = importMethod
        self.directFiles = directFiles
        self.preSkipped = preSkipped
        self.nearDuplicates = nearDuplicates
        for item in items {
            item.nearDuplicates = nearDuplicates
        }
        self.router = router
        self.services = services
        self.commit = commit
        startRefinement()
    }

    public var selected: PasteReviewItem? {
        items.first { $0.id == selectedID } ?? items.first
    }

    /// Several files under review (R96): the list with checkboxes.
    public var isBatch: Bool {
        items.count > 1
    }

    public var tickedCount: Int {
        items.count(where: \.isTicked)
    }

    /// "Accept" for one song, "Import N Songs" for a batch.
    public var acceptTitle: String {
        guard isBatch || !directFiles.isEmpty else { return "Accept" }
        let count = tickedCount + directFiles.count
        return count == 1 ? "Import 1 Song" : "Import \(count) Songs"
    }

    public var canAccept: Bool {
        phase == .review && (tickedCount > 0 || !directFiles.isEmpty) && !isClosed
    }

    // MARK: Input state

    /// Turns the input state's text (pasted with Command-V or typed) into a review.
    public func submitDraft(source: PasteSource = .newSong) {
        let text = draftText
        guard phase == .input, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        // Spec 11.4: a lone page address goes to the web field, not the converter.
        if webImportAvailable, let url = LoneWebAddress.url(in: text) {
            draftText = ""
            pendingWebInput = .address(url, .pastedURL)
            return
        }
        let item = PasteReviewItem(source: source, original: text, origin: .paste)
        item.nearDuplicates = nearDuplicates
        items = [item]
        selectedID = item.id
        phase = .review
        startRefinement()
    }

    // MARK: Web import and search (P9-4 spec 5.2)

    /// Something to read at once: the web field picks it up (spec 11.4-11.5).
    public func receive(_ input: PendingWebInput) {
        guard webImportAvailable, phase != .review else { return }
        showsPasteHint = false
        phase = .input
        pendingWebInput = input
    }

    /// Hands over the pending web input once (the web field reads it).
    public func takePendingWebInput() -> PendingWebInput? {
        defer { pendingWebInput = nil }
        return pendingWebInput
    }

    /// A page or search result read by a plugin: one item from
    /// `IngestPipeline.ingest(_:origin:source:)`, then the paste flow as for any paste.
    public func submitSource(_ song: ImportedSong, source: PasteSource) {
        guard phase != .review, !isClosed else { return }
        let item = PasteReviewItem(song: song, source: source)
        item.nearDuplicates = nearDuplicates
        items = [item]
        selectedID = item.id
        isReadingWeb = false
        phase = .review
        startRefinement()
    }

    /// Paste the Page Instead (spec 8.6): the input state, explaining how to copy the page.
    public func showPasteInstead() {
        guard phase != .review, !isClosed else { return }
        isReadingWeb = false
        showsPasteHint = true
        phase = .input
    }

    // MARK: Ticks

    public func setTicked(_ ticked: Bool, for id: PasteReviewItem.ID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.isTicked = ticked
    }

    // MARK: Accept / Cancel

    /// Writes the ticked songs, with the import's already-ChordPro files, as one import (one
    /// undo step) and closes. Refinement stops first; the songs are saved as shown. Returns
    /// the import summary (unticked files listed as not imported), or nil when nothing was
    /// written.
    @discardableResult
    public func accept() async -> ImportSummary? {
        guard canAccept else { return nil }
        stopAll()
        let ticked = items.filter(\.isTicked)
        guard var summary = await commit(directFiles + ticked.map(\.importCandidate)) else {
            return nil
        }
        summary.skipped = preSkipped + summary.skipped + items.filter { !$0.isTicked }.map {
            ImportSkip(fileName: $0.fileName ?? "Pasted song", reason: Self.untickedReason)
        }
        for item in items {
            record(item, outcome: item.isTicked ? .accepted : .unticked)
        }
        isClosed = true
        return summary
    }

    /// Writes no reviewed song and closes (the host still writes `directFiles`).
    public func cancel() {
        guard !isClosed else { return }
        stopAll()
        isReadingWeb = false
        if phase == .review {
            for item in items {
                record(item, outcome: .cancelled)
            }
        }
        isClosed = true
    }

    static let untickedReason = "Not imported (unticked in review)"

    // MARK: Refinement

    private func startRefinement() {
        queue?.cancel()
        let pending = items.filter { $0.status == .queued }
        guard !pending.isEmpty else { return }
        let router = router
        queue = Task { [weak self] in
            for item in pending {
                guard !Task.isCancelled else { return }
                await self?.refine(item, router: router)
            }
        }
    }

    /// Returns once the running refinement queue has drained (tests await this instead of
    /// polling a status against a wall-clock deadline).
    func awaitRefinement() async {
        await queue?.value
    }

    private func refine(_ item: PasteReviewItem, router: Router) async {
        guard item.status == .queued else { return }
        let first = router.policy.order(for: .sectionLabels).first
        item.refinementStarted(first)
        let clock = ContinuousClock()
        let start = clock.now
        let base = item.base
        let task = Task { @MainActor [weak item] in
            for await update in PasteRefiner.refine(base, router: router) {
                item?.apply(update)
            }
        }
        item.refinementTask = task
        await task.value
        let asked = item.reports.values.contains { !$0.attempts.isEmpty }
        let elapsed = clock.now - start
        item.refinementFinished(seconds: asked ? Self.seconds(elapsed) : nil)
    }

    private func stopAll() {
        queue?.cancel()
        queue = nil
        for item in items {
            item.stopRefinement()
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    // MARK: Analytics

    private func record(_ item: PasteReviewItem, outcome: PasteOutcome) {
        services.record(.aiPasteFinished(PasteAnalytics.summary(for: item, outcome: outcome)))
        if outcome == .accepted {
            for summary in PasteAnalytics.artistSplits(of: item) {
                services.record(.songArtistSplit(summary))
            }
        }
    }
}
