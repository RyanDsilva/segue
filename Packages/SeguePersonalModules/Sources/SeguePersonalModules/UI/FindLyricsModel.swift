import ChordPro
import Foundation
import Ingest
import Library
import Observation
import Plugins
import SegueUI
import Services

/// Find Lyrics (spec 6.4-6.11, R198 direction A): one search on Return across the three
/// sources at once, grouped in their fixed order (R182) with each group's own status line,
/// a chord site's versions nested under their song, a paced preview of the selected
/// version, and the pick handed to the review. No model touches the query (spec 6.3).
@MainActor
@Observable
final class FindLyricsModel {
    /// One song row: a chord site's song with its ranked versions, or one lyrics record.
    struct Song: Identifiable, Equatable {
        let id: String
        let group: SearchGroup
        let title: String
        let artist: String?
        let album: String?
        /// Best first (`VersionRanker` for Ultimate Guitar, the site's order otherwise).
        let versions: [SearchCandidate]
        let inLibrary: Bool

        var best: SearchCandidate {
            versions[0]
        }

        /// Nested version rows (chord sites only).
        var nests: Bool {
            group != .lyricsRecord
        }
    }

    enum Status: Equatable {
        case idle
        case searching
        /// The lyrics source's 503 retries (spec 6.8, 9).
        case retrying
        case failed(ImportFailure, ImportCopy.Message)
        case done
    }

    struct Group: Identifiable, Equatable {
        let id: SearchGroup
        let name: String
        var status = Status.idle
        var songs: [Song] = []
        /// The romanized-Hindi variant queries that ran ("Also searched").
        var variants: [String] = []
        /// The previous search's rows stay greyed while a new one runs.
        var isStale = false
    }

    /// A row of the one list: a song, or a version nested under it.
    enum Row: Hashable {
        case song(String)
        case version(String)
    }

    enum Preview: Equatable {
        case empty
        case loading(String)
        case loaded(String, ImportedSong, chordPro: String)
        case failed(String, String)
    }

    var query = ""
    var artist = ""
    var showsArtist = false
    var groups: [Group]
    var selection: Row? {
        didSet { schedulePreview() }
    }

    var expanded: Set<String> = []
    var preview = Preview.empty
    private(set) var hasSearched = false
    var openHere: OpenHereRequest?
    /// Search stays off until a busy source allows it again (spec 6.8).
    private(set) var retryAt: Date?

    @ObservationIgnored let sources: [any SongSearchSource]
    @ObservationIgnored let challenges: (any ChallengeViewSource)?
    @ObservationIgnored var host: ImportHost?
    @ObservationIgnored var tasks: [SearchGroup: Task<Void, Never>] = [:]
    @ObservationIgnored var previewTask: Task<Void, Never>?
    @ObservationIgnored var pickTask: Task<Void, Never>?
    @ObservationIgnored var cache: [String: ImportedSong] = [:]
    @ObservationIgnored var openHereGroup: SearchGroup?
    @ObservationIgnored var searchStats = SearchStats()
    @ObservationIgnored var previewsOpened = 0
    @ObservationIgnored let previewDelay: Duration
    @ObservationIgnored let now: @MainActor () -> Date

    init(
        sources: [any SongSearchSource],
        challenges: (any ChallengeViewSource)?,
        previewDelay: Duration = .milliseconds(300),
        now: @escaping @MainActor () -> Date = { Date() },
    ) {
        self.sources = sources
        self.challenges = challenges
        self.previewDelay = previewDelay
        self.now = now
        groups = sources.map { Group(id: $0.group, name: $0.displayName) }
    }

    func attach(_ host: ImportHost) {
        self.host = host
    }

    var challengeSource: (any ChallengeViewSource)? {
        challenges
    }

    var isRunning: Bool {
        groups.contains { $0.status == .searching || $0.status == .retrying }
    }

    var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
            && (retryAt.map { $0 <= now() } ?? true)
    }

    // MARK: Search

    /// Return or Search: all sources at once (spec 6.9), each group filling as it answers.
    func search() {
        guard canSearch else { return }
        cancelSearch()
        hasSearched = true
        selection = nil
        expanded = []
        preview = .empty
        searchStats = SearchStats(started: .now)
        let text = [query, artist].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let songQuery = SongQuery(text: text, artist: artist.isEmpty ? nil : artist)
        searchStats.romanHindi = LyricsQueryVariants.isRomanizedHindi(text)
        for index in groups.indices {
            groups[index].isStale = !groups[index].songs.isEmpty
            groups[index].status = .searching
            groups[index].variants = []
        }
        for source in sources {
            run(source, songQuery)
        }
    }

    func run(_ source: any SongSearchSource, _ query: SongQuery) {
        let group = source.group
        let searcher = observed(source)
        tasks[group]?.cancel()
        tasks[group] = Task { [weak self] in
            do throws(ImportFailure) {
                let found = try await searcher.search(query)
                guard !Task.isCancelled else { return }
                self?.answered(group, found)
            } catch {
                self?.failed(group, error)
            }
        }
    }

    /// The lyrics source with its variant and retry callbacks pointed at this model.
    private func observed(_ source: any SongSearchSource) -> any SongSearchSource {
        guard var lyrics = source as? LyricsSearchSource else { return source }
        lyrics.onVariants = { [weak self] variants in
            Task { @MainActor in self?.noteVariants(variants) }
        }
        lyrics.onRetry = { [weak self] count in
            Task { @MainActor in self?.noteRetry(count) }
        }
        return lyrics
    }

    func noteVariants(_ variants: [String]) {
        guard let index = groups.firstIndex(where: { $0.id == .lyricsRecord }) else { return }
        groups[index].variants = variants
        searchStats.variants = variants.count
    }

    func noteRetry(_ count: Int) {
        guard let index = groups.firstIndex(where: { $0.id == .lyricsRecord }),
              groups[index].status == .searching || groups[index].status == .retrying
        else { return }
        groups[index].status = .retrying
        searchStats.retries = max(searchStats.retries, count)
    }

    func answered(_ group: SearchGroup, _ candidates: [SearchCandidate]) {
        guard let index = groups.firstIndex(where: { $0.id == group }) else { return }
        groups[index].songs = Self.songs(candidates, group: group, library: host?.nearDuplicates)
        groups[index].status = .done
        groups[index].isStale = false
        searchStats.answered(results: candidates.count)
        // The first answer selects the best version of the first song (spec 6.10).
        if selection == nil, let first = groups[index].songs.first {
            if first.nests, first.versions.count > 1 {
                expanded.insert(first.id)
                selection = .version(key(group, first.best))
            } else {
                selection = .song(first.id)
            }
        }
        finishIfDone()
    }

    func failed(_ group: SearchGroup, _ failure: ImportFailure) {
        guard failure != .cancelled,
              let index = groups.firstIndex(where: { $0.id == group }) else { return }
        let message = ImportCopy.search(failure, source: groups[index].name, now: now())
        groups[index].status = .failed(failure, message)
        groups[index].songs = []
        groups[index].isStale = false
        if group == .lyricsRecord, let until = message.retryAt, case .busy = failure {
            retryAt = until
        }
        searchStats.failed(failure)
        finishIfDone()
    }

    func finishIfDone() {
        guard !isRunning, let started = searchStats.started else { return }
        let total = groups.reduce(0) { $0 + $1.songs.reduce(0) { $0 + $1.versions.count } }
        host?.record(.importSearched(SongSearchedSummary(
            results: SmallBucket(total),
            groupsWithResults: SmallBucket(groups.count { !$0.songs.isEmpty }),
            groupsFailed: SmallBucket(groups.count {
                if case .failed = $0.status {
                    return true
                }
                return false
            }),
            lyricsRetries: SmallBucket(searchStats.retries),
            variants: SmallBucket(searchStats.variants),
            outcome: searchStats.outcome(results: total),
            romanHindiQuery: searchStats.romanHindi,
            latency: LatencyBucket(seconds: searchStats.firstAnswer.map {
                ($0 - started) / .seconds(1)
            } ?? (ContinuousClock.now - started) / .seconds(1)),
        )))
        searchStats.started = nil
    }

    /// Esc: a running search is cancelled first; with nothing running the sheet closes.
    func escape() {
        if isRunning {
            cancelSearch()
            if let started = searchStats.started {
                searchStats.cancelled = true
                searchStats.started = started
                finishIfDone()
            }
        } else {
            host?.cancel()
        }
    }

    func cancelSearch() {
        for task in tasks.values {
            task.cancel()
        }
        tasks = [:]
        for index in groups.indices
            where groups[index].status == .searching || groups[index].status == .retrying
        {
            groups[index].status = groups[index].songs.isEmpty ? .idle : .done
            groups[index].isStale = false
        }
    }

    /// Songs from a group's candidates in their order: versions nest by `songKey`.
    static func songs(
        _ candidates: [SearchCandidate],
        group: SearchGroup,
        library: NearDuplicateIndex?,
    ) -> [Song] {
        var order: [String] = []
        var versions: [String: [SearchCandidate]] = [:]
        for candidate in candidates {
            let key = group == .lyricsRecord ? candidate.id : (candidate.songKey ?? candidate.id)
            if versions[key] == nil {
                order.append(key)
            }
            versions[key, default: []].append(candidate)
        }
        return order.compactMap { key in
            guard let list = versions[key], let best = list.first else { return nil }
            return Song(
                id: "\(group.rawValue)/\(key)",
                group: group,
                title: best.title,
                artist: best.artist,
                album: best.album,
                versions: list,
                inLibrary: inLibrary(best, library: library),
            )
        }
    }

    /// "In your library" (spec 5.3): the near-duplicate index over the title, the split
    /// credit and, when the search returned them, the plain lyrics. A hint only.
    static func inLibrary(_ candidate: SearchCandidate, library: NearDuplicateIndex?) -> Bool {
        guard let library else { return false }
        let artists = candidate.artist.map { ArtistNames.split($0).parts } ?? []
        return library.match(
            title: candidate.title,
            artists: artists,
            lyrics: candidate.lyrics ?? "",
            contentHash: "search/\(candidate.id)",
        ) != nil
    }
}
