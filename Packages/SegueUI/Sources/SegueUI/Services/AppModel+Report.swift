#if os(macOS)
    import Foundation
    import Library
    import Services

    extension AppModel {
        /// A fresh Report a Problem form for the library as it is now, its message starting
        /// as `message`.
        func makeReportModel(message: String = "") -> ReportProblemModel {
            let session = session
            let model = ReportProblemModel(context: ReportProblemModel.Context(
                services: services,
                consent: dependencies.consent.state,
                diagnostics: dependencies.diagnostics,
                mail: dependencies.mail,
                clock: dependencies.clock,
                flavor: dependencies.flavor,
                library: SystemInfo.LibraryCounts(
                    songs: session?.library.catalog.count ?? 0,
                    setlists: session?.setlists.setlists.count ?? 0,
                    gigs: session?.gigLog.entries.count ?? 0,
                ),
                currentSong: { [weak self] in self?.currentSongFiles() },
                log: diagnosticLog,
            ))
            model.message = message
            return model
        }

        /// The error banner's Report... (P9-5 5, P1): Report a Problem with what the banner
        /// said already in the message, counted apart from the Help menu's. Never on stage
        /// (the banner hides while a show is up).
        func reportBannerError(_ message: String, code: ErrorCode) {
            guard !isShowUp else { return }
            services.record(.helpOpened(.reportProblem, from: .errorBanner))
            dependencies.reportPresenter.present(prefill: Self.bannerReport(message, code: code))
        }

        /// The message a banner report starts with: the error's code and the banner's text,
        /// then room for what the musician was doing.
        static func bannerReport(_ message: String, code: ErrorCode) -> String {
            "Segue showed this error (\(code.rawValue)): \(message)\n\nWhat I was doing: "
        }

        /// Help > Request a Feature and the report form's link: the board in the browser.
        func requestFeature() {
            services.record(.helpOpened(.requestFeature))
            dependencies.hooks.requestFeature(dependencies.workspace)
        }

        /// The selected song's `.cho` and its sidecar, read through the library's file
        /// system (security-scoped); nil when no song is selected or it cannot be read.
        func currentSongFiles() -> ReportProblemModel.SongFiles? {
            guard let session, let id = session.library.selection,
                  let record = session.library.song(id: id)
            else {
                return nil
            }
            let fileSystem = session.stores.fileSystem
            let song = session.root.url.appending(path: record.relativePath)
            guard let source = try? fileSystem.readData(at: song) else { return nil }
            var files = [FeedbackAttachment(kind: .songFile, file: DiagnosticFile(
                name: song.lastPathComponent,
                contentType: "text/plain",
                data: source,
            ))]
            let sidecar = song.deletingPathExtension().appendingPathExtension("segue.json")
            if let data = try? fileSystem.readData(at: sidecar) {
                files.append(FeedbackAttachment(kind: .songSidecar, file: DiagnosticFile(
                    name: sidecar.lastPathComponent,
                    contentType: "application/json",
                    data: data,
                )))
            }
            return ReportProblemModel.SongFiles(
                title: LibraryViewModel.sortTitle(record),
                files: files,
            )
        }
    }
#endif
