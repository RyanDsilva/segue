import Foundation
import Ingest
import Plugins
import SegueUI
import Services

extension FindLyricsModel {
    // MARK: Preview (spec 6.4, 9: 300 ms on a row before fetching)

    func schedulePreview() {
        previewTask?.cancel()
        guard let selection, let (song, candidate) = candidate(for: selection) else {
            preview = .empty
            return
        }
        let key = key(song.group, candidate)
        if let cached = cache[key] {
            preview = .loaded(key, cached, chordPro: Self.chordPro(cached))
            return
        }
        guard !candidate.unsupportedScript else {
            preview = .failed(key, "In a script Segue doesn't show.")
            return
        }
        guard !candidate.isInstrumental else {
            preview = .failed(key, "An instrumental has no lyrics.")
            return
        }
        preview = .loading(key)
        guard let source = sources.first(where: { $0.group == song.group }) else { return }
        let delay = previewDelay
        previewTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            do throws(ImportFailure) {
                let imported = try await source.song(for: candidate)
                self?.previewed(key, imported)
            } catch {
                self?.previewFailed(key, error, song: song)
            }
        }
    }

    func previewed(_ key: String, _ song: ImportedSong) {
        cache[key] = song
        previewsOpened += 1
        guard case .loading(key) = preview else { return }
        preview = .loaded(key, song, chordPro: Self.chordPro(song))
    }

    func previewFailed(_ key: String, _ failure: ImportFailure, song: Song) {
        guard failure != .cancelled, case .loading(key) = preview else { return }
        let name = groups.first { $0.id == song.group }?.name ?? ""
        preview = .failed(key, ImportCopy.search(failure, source: name, now: now()).text)
    }

    /// The chart as it will import: the source's fields over the text (spec 5.1).
    static func chordPro(_ song: ImportedSong) -> String {
        let origin: IngestOrigin = song.provenance.reader == .lyricsRecord ? .lyrics : .web
        return IngestPipeline.ingest(song.text, origin: origin, source: song.fields).text
    }

    // MARK: Pick

    /// Return, double-click or Review: the selected version into the review sheet.
    func pick() {
        guard pickTask == nil, let host, let selection,
              let (song, candidate) = candidate(for: selection), candidate.isPickable,
              let source = sources.first(where: { $0.group == song.group })
        else { return }
        let key = key(song.group, candidate)
        let cached = cache[key]
        let rank = (groups.first { $0.id == song.group }?.songs.firstIndex(of: song) ?? 0) + 1
        let versionRank = song.nests ? (song.versions.firstIndex(of: candidate) ?? 0) + 1 : 0
        pickTask = Task { [weak self] in
            defer { self?.pickTask = nil }
            let imported: ImportedSong
            if let cached {
                imported = cached
            } else {
                do throws(ImportFailure) {
                    imported = try await source.song(for: candidate)
                } catch {
                    self?.previewFailed(key, error, song: song)
                    return
                }
            }
            var resolved = imported
            resolved.fields = await FilmTitleResolver.resolve(imported.fields, router: host.router)
            guard let self, !Task.isCancelled else { return }
            host.record(.importSearchPicked(SearchPickedSummary(
                group: ImportCopy.group(song.group),
                rank: SmallBucket(rank),
                versionRank: SmallBucket(versionRank),
                previews: SmallBucket(previewsOpened),
                fromVariant: false,
                romanized: candidate.romanized || imported.provenance.romanized,
                inLibrary: song.inLibrary,
            )))
            cancelSearch()
            host.review.submitSource(resolved, source: .songSearch)
        }
    }

    var isPicking: Bool {
        pickTask != nil
    }

    // MARK: Group actions

    func perform(_ action: ImportCopy.Action, in group: SearchGroup) {
        switch action {
        case .tryAgain:
            if let source = sources.first(where: { $0.group == group }),
               let index = groups.firstIndex(where: { $0.id == group })
            {
                groups[index].status = .searching
                searchStats = SearchStats(started: .now)
                run(source, SongQuery(text: query, artist: artist.isEmpty ? nil : artist))
            }
        case .openHere:
            if let url = SearchSite.searchURL(group, query: query) {
                openHereGroup = group
                openHere = OpenHereRequest(url: url)
            }
        case .openInBrowser, .searchInBrowser:
            SearchSite.searchURL(group, query: query).map { host?.open($0) }
        case .importSavedPage, .pasteInstead:
            host?.review.showPasteInstead()
        }
    }

    /// Open Here closed: after a completed check that group searches again.
    func openHereFinished(cleared: Bool) {
        openHere = nil
        defer { openHereGroup = nil }
        guard cleared, let group = openHereGroup else { return }
        perform(.tryAgain, in: group)
    }

    func openInBrowser() {
        guard let selection, let (_, candidate) = candidate(for: selection),
              let url = candidate.pageURL else { return }
        host?.open(url)
    }

    func openSite(_ group: SearchGroup) {
        host?.open(SearchSite.home(group))
    }
}
