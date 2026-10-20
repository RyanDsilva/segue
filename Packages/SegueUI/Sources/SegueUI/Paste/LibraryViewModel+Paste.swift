import Foundation
import Ingest
import Library
import Services

// Routes into the paste review sheet (spec 6.1, R75, R83, R95/R109): New Song's input state,
// a pasted song, and import files that need conversion. During a show every route into the
// sheet is disabled (R109): New Song goes straight to Start blank, and only files that are
// already ChordPro import.

public extension LibraryViewModel {
    /// Why paste is unavailable now (help text on disabled controls), or nil when it works.
    var pasteUnavailableReason: String? {
        isPerforming ? Self.pasteDuringShowReason : nil
    }

    /// Whether a route into the review sheet may open now (R109).
    var canPaste: Bool {
        pasteUnavailableReason == nil && pasteReview == nil
    }

    static let pasteDuringShowReason = "Paste is unavailable while a show is running"

    /// New Song (R83): the review sheet's input state; during a show, Start blank at once.
    func beginNewSongFlow() {
        guard !isPerforming else {
            startBlank()
            return
        }
        guard pasteReview == nil else { return }
        pasteReview = makeReview(items: [])
    }

    /// Opens the review sheet on pasted `text` (File > New Song from Clipboard, the empty
    /// library's Paste a Song, Command-V on the song list). Blank text and a show running
    /// do nothing; the caller shows `pasteUnavailableReason`.
    func beginPasteReview(text: String, source: PasteSource) {
        guard canPaste, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let item = PasteReviewItem(source: source, original: text, origin: .paste)
        pasteReview = makeReview(items: [item])
    }

    /// "Start blank": closes the sheet (writing nothing) and opens the new-song editor with
    /// the song card focused on Title.
    func startBlank() {
        pasteReview?.cancel()
        pasteReview = nil
        beginNewSong()
        SongCardFocusRouter.shared.focus(.title)
    }

    /// Accept: writes the reviewed songs as one undoable import, closes the sheet and shows
    /// them like any import (unticked batch files listed as not imported).
    func acceptPasteReview() async {
        guard let review = pasteReview else { return }
        await flushEditor()
        guard let summary = await review.accept() else { return }
        pasteReview = nil
        if let method = review.importMethod {
            await finishImport(summary, files: review.items.count, method: method)
        } else {
            await reload()
            if !summary.imported.isEmpty {
                recordSongsCreated(.newSong)
            }
            showImported(summary, bar: !summary.skipped.isEmpty)
        }
    }

    /// Cancel: writes nothing and closes the sheet.
    func cancelPasteReview() {
        pasteReview?.cancel()
        pasteReview = nil
    }

    /// Import with review (R96, A29, R109): files that are already ChordPro import directly
    /// (one undoable import); files that need conversion open ONE review sheet listing
    /// every one of them. During a show conversion files are left out with the reason.
    func importWithReview(_ urls: [URL], method: ImportMethod = .dragDrop) async {
        guard canImport || isPerforming, !urls.isEmpty, pasteReview == nil else { return }
        await flushEditor()
        let prepared: ([ImportCandidate], [ImportSkip])
        do {
            prepared = try await store.prepareImport(urls)
        } catch {
            errorMessage = UserMessage.describe(error)
            services.record(.errorOccurred(.importFailed))
            return
        }
        var direct: [ImportCandidate] = []
        var review: [PasteReviewItem] = []
        var skipped = prepared.1
        for candidate in prepared.0 {
            let ext = candidate.source.pathExtension.lowercased()
            let result = IngestPipeline.ingest(candidate.text, origin: .file(extension: ext))
            if result.isAlreadyChordPro {
                direct.append(candidate)
            } else if isPerforming {
                skipped.append(ImportSkip(
                    fileName: candidate.fileName,
                    reason: Self.pasteDuringShowReason,
                ))
            } else {
                review.append(PasteReviewItem(
                    source: ext == "crd" ? .fileCrd : .fileTxt,
                    original: candidate.text,
                    fileName: candidate.fileName,
                    candidate: candidate,
                    origin: .file(extension: ext),
                ))
            }
        }
        var summary = ImportSummary(skipped: skipped)
        if !direct.isEmpty {
            do {
                let written = try await store.commitImport(direct)
                summary.imported = written.imported
                summary.converted = written.converted
                summary.skipped += written.skipped
            } catch {
                errorMessage = UserMessage.describe(error)
            }
        }
        await finishImport(summary, files: urls.count, method: method)
        guard !review.isEmpty else { return }
        pasteReview = makeReview(items: review, method: method)
    }
}

extension LibraryViewModel {
    func makeReview(items: [PasteReviewItem], method: ImportMethod? = nil) -> PasteReviewModel {
        PasteReviewModel(
            items: items,
            importMethod: method,
            router: aiRouter,
            services: services,
        ) { [weak self] candidates in
            await self?.writeReviewed(candidates)
        }
    }

    /// Writes reviewed songs (nil when the write failed; the error is shown).
    private func writeReviewed(_ candidates: [ImportCandidate]) async -> ImportSummary? {
        do {
            return try await store.commitImport(candidates)
        } catch {
            errorMessage = UserMessage.describe(error)
            services.record(.errorOccurred(.importFailed))
            return nil
        }
    }
}
