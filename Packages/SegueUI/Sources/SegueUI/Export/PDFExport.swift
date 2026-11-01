#if os(macOS)
    import Foundation
    import LiveLayout
    import PDFKit
    import Printing

    /// One render of an export (P9-1 spec 7.2): requests on the main actor, each song's
    /// pagination off it (one child task per song), then the drawing back on the main actor.
    @MainActor
    enum PDFExport {
        struct Output {
            var pdf: PDFDocument
            var document: PrintDocument
            var job: PrintJob
            var diagrams: [Int: PrintSongDiagrams]
        }

        static func make(_ snapshot: PDFSnapshot, options: PrintOptions) async throws -> Output {
            let job = PrintRequests.job(snapshot, options: options)
            let laid = try await layout(job)
            let document = PrintAssembler.assemble(job, laid: laid)
            let diagrams = diagrams(job)
            let pdf = try await PDFRenderer.render(document, diagrams: diagrams)
            return Output(pdf: pdf, document: document, job: job, diagrams: diagrams)
        }

        /// Every song paginated concurrently with Core Text metrics.
        static func layout(_ job: PrintJob) async throws -> [LaidSong] {
            try await withThrowingTaskGroup(of: (Int, LaidSong).self) { group in
                for (index, song) in job.songs.enumerated() {
                    group.addTask(priority: .userInitiated) {
                        try Task.checkCancellation()
                        return (
                            index,
                            PrintAssembler.layout(song, job: job, metrics: StageTextMetrics()),
                        )
                    }
                }
                var laid = [LaidSong?](repeating: nil, count: job.songs.count)
                for try await (index, song) in group {
                    laid[index] = song
                }
                return laid.compactMap(\.self)
            }
        }

        /// The diagrams of each song that prints them.
        static func diagrams(_ job: PrintJob) -> [Int: PrintSongDiagrams] {
            var result: [Int: PrintSongDiagrams] = [:]
            for (index, song) in job.songs.enumerated() where song.diagrams != nil {
                let model = song.request.model
                result[index] = PrintSongDiagrams(
                    diagrams: model.diagrams,
                    instrument: model.transform.options.instrument,
                    tuning: model.tuning,
                )
            }
            return result
        }
    }
#endif
