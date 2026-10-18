#if os(macOS)
    import Foundation
    import Library
    import Setlists
    import Support

    // WS2b 4.1: when the Welcome flow shows, how it moves from page to page and how it ends.
    // First-run order: library, Welcome songs, consent (I-7).

    extension AppModel {
        // MARK: Launch

        /// No library chosen yet (the chooser's first-launch case): a genuinely new install
        /// gets the full flow; one that finished it before but lost its bookmark does not.
        func beginOnboardingWithoutLibrary() {
            let store = polish.onboarding
            guard !store.isCompleted else { return }
            store.markStarted()
            onboarding.begin(flowPages(includingLibrary: true), at: .library)
        }

        /// The stored library opened at launch: an upgrader is marked done silently, an
        /// unfinished flow resumes with only its unanswered pages.
        func continueOnboardingAfterStoredLibrary() {
            let store = polish.onboarding
            switch store.completed {
            case nil:
                // A pre-WS2b install: nothing shown, never seeded (A10). WS3's own consent
                // sheet asks an undecided upgrader.
                store.markUpgrader()
            case false?:
                resumeOnboarding()
            case true?:
                break
            }
        }

        /// The test override library opened: `-SegueOnboarding fresh` runs the flow from
        /// page 2, `done` marks it finished, and no flag treats it as done (so the rest of
        /// the E2E suite never sees it). A real override never exists outside Debug.
        func applyOnboardingOverride() async {
            let store = polish.onboarding
            switch polish.launch.onboarding {
            case .fresh?:
                store.resetForTesting()
                store.markStarted()
                onboarding.begin(flowPages(includingLibrary: true), at: .welcomeSongs)
                await preparePageTwo()
            case .done?:
                store.markCompleted()
            case nil:
                break
            }
        }

        /// Page 2 if the Welcome songs were never answered, page 3 if consent is still open;
        /// with neither, the flow is quietly done.
        private func resumeOnboarding() {
            let store = polish.onboarding
            var pages: [OnboardingModel.Page] = []
            if store.decision == nil {
                pages.append(.welcomeSongs)
            }
            if dependencies.consent.needsPrompt {
                pages.append(.consent)
            }
            guard let first = pages.first else {
                store.markCompleted()
                return
            }
            onboarding.begin(pages, at: first)
            if first == .welcomeSongs {
                Task { await preparePageTwo() }
            }
        }

        private func flowPages(includingLibrary: Bool) -> [OnboardingModel.Page] {
            var pages: [OnboardingModel.Page] = includingLibrary ? [.library] : []
            pages.append(.welcomeSongs)
            if dependencies.consent.needsPrompt {
                pages.append(.consent)
            }
            return pages
        }

        // MARK: Page 1

        /// "Create Library in Music…" / "Choose Existing Folder…": the panel, then page 2 once
        /// the library is open. A cancelled panel changes nothing; a failure shows inline.
        func onboardingChooseLibrary(create: Bool) async {
            guard onboarding.page == .library, !onboarding.isChoosingFolder else { return }
            onboarding.isChoosingFolder = true
            onboarding.libraryError = nil
            if create {
                await createLibrary()
            } else {
                await chooseLibrary()
            }
            onboarding.isChoosingFolder = false
            switch state {
            case .ready:
                onboarding.page = .welcomeSongs
                await preparePageTwo()
            case let .needsLibrary(.openFailed(message)):
                onboarding.libraryError = LibraryChooserView.message(for: .openFailed(message))
                state = .needsLibrary(.firstLaunch)
            case let .needsLibrary(reason) where reason == .inUseByAnotherCopy:
                onboarding.libraryError = Self.inUseMessage
                state = .needsLibrary(.firstLaunch)
            default:
                break
            }
        }

        // MARK: Page 2

        /// The checkbox default: on when the library has no songs, off when it has any.
        private func preparePageTwo() async {
            guard let session else { return }
            onboarding.addsWelcomeSongs = session.hasNoSongs
        }

        /// Continue on page 2: seed (when ticked), record the answer, then page 3 or finish.
        func onboardingContinueFromWelcomeSongs() async {
            guard onboarding.mode == .flow, onboarding.page == .welcomeSongs,
                  onboarding.seedState != .seeding
            else { return }
            if onboarding.addsWelcomeSongs {
                guard await seedWelcomeLibrary() else { return }
                polish.onboarding.record(.added)
            } else {
                polish.onboarding.record(.declined)
            }
            advancePastWelcomeSongs()
        }

        /// "Skip" after a failed seed: songs already written stay (they carry the tag).
        func onboardingSkipWelcomeSongs() {
            guard onboarding.mode == .flow, onboarding.page == .welcomeSongs else { return }
            polish.onboarding.record(.declined)
            advancePastWelcomeSongs()
        }

        private func advancePastWelcomeSongs() {
            onboarding.seedState = .idle
            if onboarding.pages.contains(.consent), dependencies.consent.needsPrompt {
                onboarding.page = .consent
            } else {
                finishOnboarding()
            }
        }

        // MARK: Page 3 and finishing

        /// Continue on page 3, after the hosted `ConsentChoiceView` committed its answers.
        func onboardingFinishConsent() {
            guard onboarding.mode == .flow, onboarding.page == .consent,
                  !dependencies.consent.needsPrompt
            else { return }
            finishOnboarding()
        }

        /// The last page is answered: done, and this release's notes count as seen (a fresh
        /// install never gets What's New).
        private func finishOnboarding() {
            polish.onboarding.markCompleted()
            polish.whatsNew.markSeen(polish.appVersion)
            onboarding.close()
            launchPromptShown = true
        }

        // MARK: Revisit (Help > Welcome to Segue…)

        /// Opens the Welcome page on its own (never the consent page). Not while performing.
        public func showWelcomeRevisit() {
            guard let session, !isPerforming, !isStartingShow, onboarding.mode == nil,
                  let folder = polish.welcomeFolder
            else { return }
            Task {
                let has = await session.hasSeedSongs(fromManifestFolder: folder)
                guard onboarding.mode == nil else { return }
                onboarding.beginRevisit(hasWelcomeSongs: has)
            }
        }

        /// "Add Welcome Songs" in revisit mode.
        func onboardingAddWelcomeSongs() async {
            guard onboarding.mode == .revisit, onboarding.seedState != .seeding else { return }
            if await seedWelcomeLibrary() {
                onboarding.seedState = .idle
                onboarding.hasWelcomeSongs = true
            }
        }

        func closeWelcomeRevisit() {
            guard onboarding.mode == .revisit, onboarding.seedState != .seeding else { return }
            onboarding.close()
        }

        // MARK: Seeding

        /// Seeds the Welcome library into the open library and records it. Idempotent.
        /// Returns false (and sets the failure text) when it could not.
        @discardableResult
        func seedWelcomeLibrary() async -> Bool {
            guard let session, let folder = polish.welcomeFolder else {
                onboarding.seedState = .failed("the Welcome songs are missing from Segue")
                return false
            }
            onboarding.seedState = .seeding
            let known = polish.onboarding.seed.flatMap { record in
                record.libraryPath == session.root.url.path(percentEncoded: false)
                    ? record.setlistID.flatMap(ULID.init(string:)).map(SetlistID.init) : nil
            }
            do {
                let outcome = try await session.seed(
                    fromManifestFolder: folder,
                    knownSetlistID: known,
                )
                polish.onboarding.recordSeed(OnboardingStore.SeedRecord(
                    seededAt: dependencies.clock.now(),
                    libraryPath: session.root.url.path(percentEncoded: false),
                    songIDs: outcome.songIDs.map(\.description),
                    setlistID: outcome.setlistID?.description,
                ))
                onboarding.seedState = .idle
                return true
            } catch {
                onboarding.seedState = .failed(UserMessage.describe(error))
                return false
            }
        }

        /// `-SegueSeedWelcome YES`: seed once the library is open, before the first frame
        /// settles. Never wipes anything.
        func seedWelcomeForLaunchIfAsked() async {
            guard polish.launch.seedWelcome, session != nil else { return }
            await seedWelcomeLibrary()
            onboarding.seedState = .idle
        }
    }
#endif
