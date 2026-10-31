import Foundation
import Library
import ModelPort
import Observation
import Services
import SetAssistant
import Setlists
import Support

/// The set assistant's command bar (P3-7, spec 7, R65, R114-R116): the request text, its
/// chips (lexicon instantly; local-model suggestions after 0.8 s idle, dashed until
/// accepted), Build / Rebuild into the open setlist, and the last build's scores.
///
/// No model runs with the AI toggle off, during a show (the router's gate) or without a
/// downloaded local model (R116: set requests never go to Foundation Models).
@MainActor
@Observable
final class SetAssistantModel {
    /// The request as typed. Each change re-reads the lexicon at once and restarts the
    /// model pass's idle timer.
    var text = "" {
        didSet {
            if text != oldValue {
                textChanged()
            }
        }
    }

    private(set) var lexicon = LexiconResult()
    /// Chips added or accepted by hand; they win over the lexicon's.
    private(set) var confirmed: [RequestChip] = []
    /// Lexicon chips the user removed (by slot), until the field is cleared.
    private(set) var removed: Set<String> = []
    /// The model's suggestions (dashed until accepted).
    private(set) var suggested: [RequestChip] = []
    private(set) var isSuggesting = false
    private(set) var isBuilding = false
    /// The last build of this bar, for the status line and the row scores.
    private(set) var result: Result?

    /// What a build left for the status line and the score popovers.
    struct Result {
        var setlist: SetlistID
        var request: SetRequest
        var library: AssistantLibrary
        var seed: UInt64
        var target: TimeInterval?
        var matching: Int
        var leftOutNoTime: [SongID]
        var tolerance: TimeInterval
    }

    @ObservationIgnored private let setlists: SetlistsViewModel
    @ObservationIgnored private let library: LibraryViewModel
    /// The library's smart filters (the builder view keeps it current).
    @ObservationIgnored var smartFilters: [SmartFilter] = []
    @ObservationIgnored private let idleDelay: Duration
    @ObservationIgnored private let builder: SetBuilder
    @ObservationIgnored private let ids = ULIDGenerator(clock: SystemClock())
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    /// Analytics for the next build: suggestions shown and accepted, the provider that
    /// answered (closed vocabulary, no text).
    @ObservationIgnored private var shownCount = 0
    @ObservationIgnored private var acceptedCount = 0
    @ObservationIgnored private var answeredBy: ProviderKind?
    @ObservationIgnored private var builds = 0

    init(
        setlists: SetlistsViewModel,
        library: LibraryViewModel,
        config: AssistantConfig = SetAssistantModel.bundledConfig,
        idleDelay: Duration = .milliseconds(800),
    ) {
        self.setlists = setlists
        self.library = library
        self.idleDelay = idleDelay
        builder = SetBuilder(config: config)
    }

    /// The bundled weights (`AIConfig/assistant.json`), else the defaults.
    static let bundledConfig: AssistantConfig = {
        guard let url = Bundle.module.url(
            forResource: "assistant", withExtension: "json", subdirectory: "AIConfig",
        ),
            let data = try? Data(contentsOf: url),
            let config = try? AssistantConfig.decode(data)
        else { return .standard }
        return config
    }()

    // MARK: Chips

    /// Every chip in order: stated ones (lexicon, minus removed; confirmed ones win), then
    /// suggestions for slots nobody stated.
    var chips: [RequestChip] {
        var chips = lexicon.chips
            .map { RequestChip($0, origin: .lexicon) }
            .filter { !removed.contains($0.id) }
        for chip in confirmed {
            chips.merge(chip)
        }
        for chip in suggested {
            chips.merge(chip)
        }
        return chips
    }

    /// The request the applied chips make.
    var request: SetRequest {
        SetRequest(chips: chips)
    }

    /// Whether Build has anything to go on.
    var canBuild: Bool {
        !isBuilding && chips.contains(where: \.isApplied)
    }

    /// A smart filter chip's name.
    func filterName(_ id: SmartFilterID) -> String? {
        smartFilters.first { $0.id == id }?.name
    }

    /// Accepts a suggestion (it applies from now on).
    func accept(_ chip: RequestChip) {
        guard chip.origin == .suggested else { return }
        suggested.removeAll { $0.id == chip.id }
        confirmed.merge(RequestChip(chip.kind, origin: .confirmed))
        acceptedCount += 1
    }

    /// Removes a chip: a suggestion is dismissed, a stated chip stops applying.
    func remove(_ chip: RequestChip) {
        suggested.removeAll { $0.id == chip.id }
        confirmed.removeAll { $0.id == chip.id }
        if lexicon.chips.contains(where: { $0.slot == chip.id }) {
            removed.insert(chip.id)
        }
    }

    /// Adds a chip by hand (or replaces the chip of its slot).
    func add(_ kind: SetChip) {
        removed.remove(kind.slot)
        suggested.removeAll { $0.id == kind.slot }
        confirmed.merge(RequestChip(kind, origin: .confirmed))
    }

    private var libraryTags: [String] {
        library.tags.map(\.tag)
    }

    private func makeLexicon() -> SetRequestLexicon {
        SetRequestLexicon(
            tags: libraryTags,
            smartFilters: smartFilters.map { SmartFilterName(id: $0.id, name: $0.name) },
            artists: library.knownArtists,
            albums: library.knownAlbums,
        )
    }

    private func textChanged() {
        lexicon = makeLexicon().parse(text)
        if text.allSatisfy(\.isWhitespace) {
            removed = []
            confirmed = []
        }
        suggestionTask?.cancel()
        suggested = []
        isSuggesting = false
        guard let task = SuggestedChips.task(for: lexicon, libraryTags: libraryTags) else {
            return
        }
        let delay = idleDelay
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.suggest(task)
        }
    }

    /// Return: the model pass starts now instead of after the idle delay.
    func suggestNow() async {
        suggestionTask?.cancel()
        guard suggested.isEmpty,
              let task = SuggestedChips.task(for: lexicon, libraryTags: libraryTags)
        else { return }
        await suggest(task)
    }

    private func suggest(_ task: SetRequestTask) async {
        let typed = text
        isSuggesting = true
        let routed = await library.aiRouter.run(task)
        isSuggesting = false
        guard !Task.isCancelled, typed == text, let output = routed.output else { return }
        let existing = chips.filter { $0.origin != .suggested }
        suggested = SuggestedChips.suggestions(
            from: output, words: task.words, libraryTags: libraryTags, existing: existing,
        )
        shownCount += suggested.count
        answeredBy = routed.report.answeredBy?.kind
    }

    // MARK: Build

    /// Builds into setlist `id` (Build) or re-packs it with a new seed (Rebuild); locked
    /// songs and break rows stay where they are either way. One undo step.
    func build(into id: SetlistID, rebuild: Bool, defaultChangeover: Int) async {
        guard let setlist = setlists.setlist(id), setlist.readOnly == nil, !isBuilding else {
            return
        }
        isBuilding = true
        defer { isBuilding = false }
        builds += 1
        let request = request
        let seed: UInt64 = rebuild ? UInt64(builds) : 1
        let records = library.catalog
        let stats = library.playStats
        let filters = smartFilters
        let changeover = TimeInterval(setlist.changeoverSeconds ?? defaultChangeover)
        let layout = RebuildLayout(entries: setlist.entries)
        let builder = builder
        let ids = ids
        let (library, draft) = await Task.detached(priority: .userInitiated) {
            let library = AssistantLibrary(
                records: records, playStats: stats, filters: filters, now: Date(),
            )
            let draft = builder.build(
                request,
                library: library,
                layout: layout,
                changeover: changeover,
                fallbackTarget: setlist.targetDuration,
                seed: seed,
                newItemID: { SetlistItemID(ids.next()) },
            )
            return (library, draft)
        }.value
        await setlists.applyAssistantSet(
            draft.entries, target: request.targetLength, to: id, rebuilt: rebuild,
        )
        result = Result(
            setlist: id,
            request: request,
            library: library,
            seed: seed,
            target: draft.target,
            matching: draft.matchingCount,
            leftOutNoTime: draft.leftOutNoTime,
            tolerance: draft.tolerance,
        )
        recordUse(rebuilt: rebuild)
    }

    /// Each song slot's score where it stands now (the user may have moved rows since the
    /// build); empty before a build of this setlist.
    func breakdowns(for setlist: Setlist) -> [SetlistItemID: ScoreBreakdown] {
        guard let result, result.setlist == setlist.id else { return [:] }
        return builder.breakdowns(
            for: setlist.entries,
            request: result.request,
            library: result.library,
            seed: result.seed,
        )
    }

    private func recordUse(rebuilt: Bool) {
        let provider: AIProviderUsed = switch answeredBy {
        case .mlx: .mlx
        case .foundationModels: .fm
        case nil: .noProvider
        }
        let kinds = chips.map(\.kind)
        setlists.services.record(.aiAssistantUsed(AssistantUsedSummary(
            context: .builder,
            lexiconChips: SmallBucket(lexicon.chips.count),
            suggestedShown: SmallBucket(shownCount),
            suggestedAccepted: SmallBucket(acceptedCount),
            provider: provider,
            rebuilt: rebuilt,
            artistChips: kinds.contains { $0.isArtistChip },
            albumChips: kinds.contains { $0.isAlbumChip },
        )))
    }
}

extension SetChip {
    /// An artist chip, included or excluded (row 21's `segue.artistChips`).
    var isArtistChip: Bool {
        switch self {
        case .artist, .excludeArtist: true
        default: false
        }
    }

    /// A Movie / Album chip, included or excluded (row 21's `segue.albumChips`).
    var isAlbumChip: Bool {
        switch self {
        case .album, .excludeAlbum: true
        default: false
        }
    }
}
