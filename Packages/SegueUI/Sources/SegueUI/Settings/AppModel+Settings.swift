#if os(macOS)
    import Foundation
    import Library
    import Setlists
    import Support

    // WS2b 4.6: the actions behind Settings > Data.

    extension AppModel {
        /// Library-changing controls in Settings work only with a library open and no show.
        var canChangeLibraryData: Bool {
            session != nil && !isPerforming && !isStartingShow
        }

        /// Data > Add Welcome Songs (idempotent). Returns the line the pane shows.
        func addWelcomeSongsFromSettings() async -> String {
            guard canChangeLibraryData else { return "" }
            let before = session?.library.catalog.count ?? 0
            guard await seedWelcomeLibrary() else {
                let reason = if case let .failed(text) = onboarding.seedState {
                    text
                } else {
                    ""
                }
                onboarding.seedState = .idle
                return "Segue could not add the Welcome songs (\(reason))."
            }
            let added = (session?.library.catalog.count ?? 0) - before
            return added > 0 ? "Added the Welcome songs and the Welcome Set setlist."
                : "The Welcome songs are already in your library."
        }

        /// What Data > Remove Welcome Songs… would trash; nil when there is nothing to remove.
        func welcomeRemovalPlan() async -> SeedRemovalPlan? {
            guard canChangeLibraryData, let session, let folder = polish.welcomeFolder else {
                return nil
            }
            let known = polish.onboarding.seed.flatMap(\.setlistID)
                .flatMap(ULID.init(string:)).map(SetlistID.init)
            return try? await session.seedRemovalPlan(
                fromManifestFolder: folder,
                knownSetlistID: known,
            )
        }

        /// Moves the plan's songs and setlist to the Trash. Returns the line the pane shows.
        func removeWelcomeSongs(_ plan: SeedRemovalPlan) async -> String {
            guard canChangeLibraryData, let session else { return "" }
            do {
                try await session.removeSeed(plan)
                return "Moved to the Trash." + (plan.keptNote.map { " \($0)" } ?? "")
            } catch {
                return "Segue could not remove the Welcome songs (\(UserMessage.describe(error)))."
            }
        }

        /// Data > Reset Tips: TipKit's datastore is reset at the next launch.
        func resetTips() {
            polish.preferences.requestTipsReset()
        }

        /// Data > Reset All Settings… (A17): Live settings, Appearance, the default
        /// changeover, the last Settings pane and the tips. Never consent, the library,
        /// onboarding, What's New or the review counters, the shape library or the key
        /// bindings.
        func resetAllSettings() {
            liveSettings.resetToDefaults()
            polish.appearance.reset()
            ChangeoverSetting.reset()
            polish.preferences.selectedPane = nil
            polish.preferences.requestTipsReset()
        }
    }
#endif
