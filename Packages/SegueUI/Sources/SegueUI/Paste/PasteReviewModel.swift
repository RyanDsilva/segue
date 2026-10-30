import Foundation
import Ingest
import Library
import ModelPort
import Observation
import Services

// The paste review sheet's state (spec 6.1-6.2, R83, R93-R96): the New Song input state,
// one pasted song, or a batch of converted files. Look-independent: the views render it.

/// What the sheet shows.
public enum PasteReviewPhase: Equatable, Sendable {
    /// New Song (R83): "Paste or type a song"; the clipboard is never read before Command-V.
    case input
    /// One song or a batch of files under review.
    case review
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
    ///   - commit: writes the accepted songs as one import; nil when it failed.
    init(
        items: [PasteReviewItem],
        importMethod: ImportMethod? = nil,
        directFiles: [ImportCandidate] = [],
        preSkipped: [ImportSkip] = [],
        nearDuplicates: NearDuplicateIndex? = nil,
        router: Router,
        services: ServicesHub,
        commit: @escaping ([ImportCandidate]) async -> ImportSummary?,
    ) {
        phase = items.isEmpty ? .input : .review
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
        let item = PasteReviewItem(source: source, original: text, origin: .paste)
        item.nearDuplicates = nearDuplicates
        items = [item]
        selectedID = item.id
        phase = .review
        startRefinement()
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
    }
}
