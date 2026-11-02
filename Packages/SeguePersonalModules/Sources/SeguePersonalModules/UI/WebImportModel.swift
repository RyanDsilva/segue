import Foundation
import Observation
import Plugins
import SegueUI
import Services

/// The New Song sheet's web field (spec 8, 11.3): one page per Import action, read through
/// the page importer, its failure shown under the field with its actions, and the read page
/// handed to the review. Nothing is saved before the review's Accept.
@MainActor
@Observable
final class WebImportModel {
    enum State: Equatable {
        case idle
        case reading
        case failed(ImportCopy.Message)
    }

    var address = ""
    var state = State.idle
    /// The owner is completing a check in Open Here (spec 8.6).
    var openHere: OpenHereRequest?
    /// Import stays off until a busy site or a back-off allows it again.
    private(set) var retryAt: Date?

    @ObservationIgnored private let importer: WebPageImporter
    @ObservationIgnored private var host: ImportHost?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The last input read, for Try Again and Open Here.
    @ObservationIgnored private(set) var lastInput: ImportInput?
    @ObservationIgnored private var entry: WebImportEntryPoint = .sheetField
    @ObservationIgnored private var openedHere = false
    @ObservationIgnored private let now: @MainActor () -> Date

    init(importer: WebPageImporter, now: @escaping @MainActor () -> Date = { Date() }) {
        self.importer = importer
        self.now = now
    }

    var challenges: (any ChallengeViewSource)? {
        importer.services.challenges
    }

    func attach(_ host: ImportHost) {
        self.host = host
    }

    var isReading: Bool {
        state == .reading
    }

    var canImport: Bool {
        !isReading && !address.trimmingCharacters(in: .whitespaces).isEmpty
            && (retryAt.map { $0 <= now() } ?? true)
    }

    /// The pending input of the sheet (a lone pasted URL, a dropped link, a saved page).
    func readPending() {
        guard let input = host?.review.takePendingWebInput() else { return }
        switch input {
        case let .address(url, entry):
            address = url.absoluteString
            read(.url(url), entry: entry)
        case let .file(file):
            address = ""
            read(.webPageFile(file), entry: .savedFile)
        }
    }

    /// Return in the field, or Import.
    func importAddress(entry: WebImportEntryPoint? = nil) {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canImport else { return }
        guard let url = URL(string: text), WebAddress.validated(url) != nil else {
            state = .failed(ImportCopy.Message(
                text: "Segue imports web pages only (https://…).",
                actions: [],
            ))
            return
        }
        let start = entry ?? (host?.review.focusesWebField == true ? .menu : .sheetField)
        read(.url(url), entry: start)
    }

    func read(_ input: ImportInput, entry: WebImportEntryPoint) {
        task?.cancel()
        lastInput = input
        self.entry = entry
        state = .reading
        host?.review.isReadingWeb = true
        let started = ContinuousClock.now
        task = Task { [weak self, importer] in
            do throws(ImportFailure) {
                let (song, page) = try await importer.read(input)
                await self?.finish(song, page: page, started: started)
            } catch {
                self?.fail(error, started: started)
            }
        }
    }

    /// Cancel while reading; the text area comes back.
    func cancel() {
        task?.cancel()
        task = nil
        if isReading {
            state = .idle
            host?.review.isReadingWeb = false
        }
    }

    /// One of the failure's actions.
    func perform(_ action: ImportCopy.Action, chooseFile: @MainActor () async -> URL?) async {
        switch action {
        case .tryAgain:
            lastInput.map { read($0, entry: entry) }
        case .openHere:
            if case let .url(url) = lastInput {
                openHere = OpenHereRequest(url: url)
            }
        case .openInBrowser, .searchInBrowser:
            if case let .url(url) = lastInput {
                host?.open(url)
            }
        case .importSavedPage:
            if let file = await chooseFile() {
                read(.webPageFile(file), entry: .savedFile)
            }
        case .pasteInstead:
            state = .idle
            host?.review.showPasteInstead()
        }
    }

    /// Open Here closed: after a completed check the same page is read again (the hidden
    /// loads now reuse the pass); a cancelled sheet leaves the actions.
    func openHereFinished(cleared: Bool) {
        openHere = nil
        guard cleared, let input = lastInput else { return }
        openedHere = true
        read(input, entry: entry)
    }

    private func finish(
        _ song: ImportedSong,
        page: LoadedPage?,
        started: ContinuousClock.Instant,
    ) async {
        guard let host, !Task.isCancelled else { return }
        // R194: an ambiguous film song name gets the model's pick, or stays flagged.
        var resolved = song
        resolved.fields = await FilmTitleResolver.resolve(song.fields, router: host.router)
        guard !Task.isCancelled else { return }
        record(.reviewed, song: resolved, page: page, started: started)
        state = .idle
        host.review.submitSource(resolved, source: .webPage)
    }

    private func fail(_ error: ImportFailure, started: ContinuousClock.Instant) {
        host?.review.isReadingWeb = false
        guard error != .cancelled else {
            state = .idle
            return
        }
        let url: URL? = if case let .url(url) = lastInput {
            url
        } else {
            nil
        }
        let name = url.map(WebAddress.siteHost) ?? "The page"
        let message = ImportCopy.page(error, host: name, now: now())
        retryAt = message.retryAt
        state = .failed(message)
        record(ImportCopy.outcome(error), song: nil, page: nil, started: started, failure: error)
    }

    private func record(
        _ outcome: WebImportOutcome,
        song: ImportedSong?,
        page: LoadedPage?,
        started: ContinuousClock.Instant,
        failure: ImportFailure? = nil,
    ) {
        let reader: ReaderKind = song?.provenance.reader ?? lastInput.flatMap {
            importer.accepts($0)
        } ?? .genericPage
        let path = song?.provenance.loadPath ?? (entry == .savedFile ? .savedFile : .plain)
        host?.record(.importPageRead(PageReadSummary(
            reader: ImportCopy.reader(reader),
            fellBack: song?.provenance.fellBack ?? false,
            contentSearch: song?.provenance.foundByContentSearch ?? false,
            outcome: outcome,
            latency: ImportCopy.latency(since: started),
            entry: entry,
            loadPath: ImportCopy.loadPath(path),
            webKitBlocked: failure == .challenged,
            challenge: failure == .challenged ? .unknown
                : ImportCopy.challenge(page?.challenge ?? .notChallenged),
            openedHere: openedHere,
            warmUp: page?.warmUp ?? false,
        )))
        if outcome == .reviewed {
            openedHere = false
        }
    }
}
