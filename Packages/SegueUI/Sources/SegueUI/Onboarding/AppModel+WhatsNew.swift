#if os(macOS)
    import Foundation

    // WS2b 4.3: when What's New shows on launch, from Help, and what dismissing it records.

    extension AppModel {
        /// At launch, once the library is open: the sheet for a release in range with
        /// `showInApp`, a silent credit when the range has none, nothing otherwise. Never
        /// with the Welcome flow or the consent sheet in the same launch, never in a test run
        /// that did not set it up.
        func checkWhatsNewAtLaunch() {
            guard session != nil, onboarding.mode == nil, !launchPromptShown,
                  !dependencies.consent.needsPrompt,
                  !polish.launch.isTestRun || polish.launch.allowsWhatsNew,
                  let current = AppVersion(polish.appVersion)
            else { return }
            let decision = WhatsNewPolicy.atLaunch(
                changelog: Changelog.load(from: polish.changelogURL),
                lastSeen: polish.whatsNew.lastSeenVersion.flatMap(AppVersion.init),
                current: current,
            )
            switch decision {
            case let .show(content):
                whatsNew = content
            case .creditSilently:
                polish.whatsNew.markSeen(polish.appVersion)
            case .nothing:
                break
            }
        }

        /// Help > What's New in Segue: this version's notes and the two before, whatever
        /// their `showInApp`; the web changelog when the bundle has none. Never on stage.
        public func showWhatsNewFromHelp() {
            guard !isPerforming, !isStartingShow, onboarding.mode == nil else { return }
            guard let current = AppVersion(polish.appVersion) ?? AppVersion("0"),
                  let content = WhatsNewPolicy.forHelp(
                      changelog: Changelog.load(from: polish.changelogURL),
                      current: current,
                  )
            else {
                AppHooks.openChangelog(dependencies.workspace)
                return
            }
            PendingEditsGuard.shared.reopenMainWindow?()
            whatsNew = content
        }

        /// Continue, Esc or closing: this version's notes count as seen.
        func dismissWhatsNew() {
            guard whatsNew != nil else { return }
            whatsNew = nil
            if let current = AppVersion(polish.appVersion),
               polish.whatsNew.lastSeenVersion.flatMap(AppVersion.init).map({ $0 < current })
               ?? true
            {
                polish.whatsNew.markSeen(polish.appVersion)
            }
        }

        /// The sheet is on screen now: after every higher-priority launch prompt, never over
        /// the Welcome flow or the consent sheet, never while performing.
        var showsWhatsNewSheet: Bool {
            whatsNew != nil && launchUIIsClear && onboarding.mode == nil
                && !showsConsentPrompt && session != nil
        }
    }
#endif
