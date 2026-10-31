#if os(macOS)
    import Foundation
    import Library
    import Services
    import Shows
    import Support

    // App-level analytics and diagnostic log lines (WS3 spec 5 rows 2-4, 11-13 and 16; spec
    // 7 call sites). Only enums, buckets and booleans: never a title, name or path.

    extension AppModel {
        var services: ServicesHub {
            dependencies.services
        }

        var diagnosticLog: DiagnosticLog? {
            dependencies.diagnosticLog
        }

        /// Days since the first launch (stored on first use in the app's defaults).
        var daysSinceFirstLaunch: DaysBucket {
            FirstLaunch.days(
                defaults: dependencies.location.defaults,
                now: dependencies.clock.now(),
            )
        }

        /// Row 2, once the launch has settled on a library state.
        func recordLaunch() {
            let library: LaunchLibraryState = switch state {
            case .ready: .open
            case .needsLibrary(.accessLost): .accessLost
            case .needsLibrary, .opening, .starting: .chooser
            }
            services.record(.appLaunched(
                daysSinceFirstLaunch: daysSinceFirstLaunch,
                flavor: dependencies.flavor,
                library: library,
            ))
            if library == .accessLost {
                services.record(.errorOccurred(.libraryAccessLost))
            }
        }

        /// A library just opened: hands the hub to its view models and records row 3.
        func libraryOpened(_ session: LibrarySession, elapsed: Duration) async {
            let days = daysSinceFirstLaunch
            session.library.services = services
            session.library.daysSinceFirstLaunch = days
            session.setlists.services = services
            session.setlists.daysSinceFirstLaunch = days
            session.gigLog.services = services
            session.smartFilters.services = services
            session.library.aiRouter = ai.router
            liveSettings.services = services
            instrumentProfile.services = services
            sound.settings.services = services
            session.library.sound = sound
            let songs = session.library.catalog
            let gigs = await session.stores.shows.gigLog().count
            diagnosticLog?.notice(.library, "opened", [
                "songs": .bucket(SongBucket(songs.count)),
                "setlists": .bucket(SmallBucket(session.setlists.setlists.count)),
                "duration": .duration(elapsed),
            ])
            services.record(.librarySnapshot(LibrarySnapshot(
                songs: SongBucket(songs.count),
                setlists: SmallBucket(session.setlists.setlists.count),
                gigs: SmallBucket(gigs),
                welcomeSongsLeft: WelcomeSongs.left(in: songs),
                customShapes: !session.library.userShapes.entries.isEmpty,
                noTempo: SongBucket(songs.count { $0.document.metadata.tempo == nil }),
            )))
        }

        /// Row 4: the user picked or created a library folder.
        func recordLibraryChosen(_ url: URL, created: Bool) {
            let location: Services.LibraryLocation = if !created {
                .existingLibrary
            } else if url.standardizedFileURL.path(percentEncoded: false)
                == LibraryLocation.suggestedFolder.standardizedFileURL.path(percentEncoded: false)
            {
                .suggestedMusicFolder
            } else {
                .otherFolder
            }
            services.record(.libraryCreated(location))
        }

        /// Row 11 and the activation milestones, when the stage comes up.
        func recordShowStarted(_ state: ShowState, kind: Shows.ShowKind, resumed: Bool) {
            let analyticsKind = AnalyticsShowKind(kind)
            let shortcutsOn = runsShortcuts(kind)
                && LiveSettingsStore.shortcutName(liveSettings.settings.startShortcut) != nil
            services.record(.showStarted(
                kind: analyticsKind,
                songs: SmallBucket(state.record.items.count),
                resumed: resumed,
                shortcutsOn: shortcutsOn,
            ))
            services.record(.milestoneReached(
                kind == .gig ? .firstGig : .firstRehearsal,
                daysSinceFirstLaunch: daysSinceFirstLaunch,
            ))
            services.record(LifecycleCrumb.stageEntered)
            diagnosticLog?.notice(.show, "started", [
                "kind": .token(kind == .gig ? "gig" : "rehearsal"),
                "songs": .bucket(SmallBucket(state.record.items.count)),
                "resumed": .bool(resumed),
            ])
        }

        /// Row 12 (and the completed-gig milestone) for a finished run.
        func recordShowEnded(
            _ record: ShowRecord,
            autoScrollUsed: Bool,
            endedBy: ShowEndReason,
        ) {
            let played = record.items.count { $0.state == .played }
            let skipped = record.items.count { $0.state == .skipped }
            let duration = (record.endedAt ?? record.updatedAt).timeIntervalSince(record.startedAt)
            services.record(.showEnded(ShowSummary(
                kind: AnalyticsShowKind(record.kind),
                duration: DurationBucket(seconds: duration),
                played: SmallBucket(played),
                skipped: SmallBucket(skipped),
                requestsUsed: !record.requests.isEmpty,
                autoScrollUsed: autoScrollUsed,
                reordered: record.events.contains { $0.kind == .reordered },
                endedBy: endedBy,
            )))
            if record.kind == .gig, endedBy == .endShow {
                services.record(.milestoneReached(
                    .firstCompletedGig,
                    daysSinceFirstLaunch: daysSinceFirstLaunch,
                ))
            }
            diagnosticLog?.notice(.show, "ended", [
                "kind": .token(record.kind == .gig ? "gig" : "rehearsal"),
                "played": .bucket(SmallBucket(played)),
                "skipped": .bucket(SmallBucket(skipped)),
            ])
        }

        /// Row 16 for an error the user was shown (and the diagnostic log line).
        func recordError(_ code: ErrorCode, _ error: (any Error)? = nil) {
            services.record(.errorOccurred(code))
            if let error {
                diagnosticLog?.error(.app, "error", ["code": .token(code.token), "error": .error(
                    LoggedError(error),
                )])
            } else {
                diagnosticLog?.error(.app, "error", ["code": .token(code.token)])
            }
        }
    }

    extension AnalyticsShowKind {
        init(_ kind: Shows.ShowKind) {
            self = kind == .gig ? .gig : .rehearsal
        }
    }

    extension ErrorCode {
        /// The code as a log token (`StaticString`, so the log stays typed).
        var token: StaticString {
            switch self {
            case .libraryAccessLost: "libraryAccessLost"
            case .libraryOpenFailed: "libraryOpenFailed"
            case .indexRebuildFailed: "indexRebuildFailed"
            case .saveConflict: "saveConflict"
            case .saveFailed: "saveFailed"
            case .importFailed: "importFailed"
            case .showStartFailed: "showStartFailed"
            case .showResumeFailed: "showResumeFailed"
            case .shapeLibraryUnreadable: "shapeLibraryUnreadable"
            case .bindingsUnreadable: "bindingsUnreadable"
            case .sectionNoteGone: "sectionNoteGone"
            case .soundBankLoad: "soundBankLoad"
            case .other: "other"
            }
        }
    }

    /// How many of the seeded Welcome songs are still in the library (row 3).
    enum WelcomeSongs {
        /// The seed manifest shipped in the app (WS2b 4.2), read once.
        static let manifest: SeedManifest? = Bundle.module
            .url(forResource: "WelcomeLibrary", withExtension: nil)
            .flatMap { try? Data(contentsOf: $0.appending(path: SeedManifest.fileName)) }
            .flatMap { try? JSONDecoder().decode(SeedManifest.self, from: $0) }

        static func left(in songs: [SongRecord]) -> WelcomeSongsLeft {
            guard let manifest, !manifest.songs.isEmpty else { return .noneLeft }
            let left = songs.count { $0.sidecar.tags.contains(manifest.tag) }
            if left == 0 {
                return .noneLeft
            }
            return left >= manifest.songs.count ? .all : .some
        }
    }
#endif
