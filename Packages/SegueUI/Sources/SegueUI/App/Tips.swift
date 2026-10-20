// TipKit's #Rule predicates support `count == 0` but not `isEmpty`.
// swiftformat:disable isEmpty

#if os(macOS)
    import Foundation
    import TipKit

    // WS2b 4.4: five contextual tips, at most one a day, only in the main window, never on
    // stage, in the pre-show checklist, over the Welcome flow, the consent sheet or What's New.

    /// The shared TipKit state: the global parameters `AppModel` keeps current, the events the
    /// views donate, and `configure` at launch.
    public enum SegueTips {
        // The Parameter macro needs explicit types.
        // swiftformat:disable redundantType propertyTypes

        // MARK: Global rules (every tip)

        @Parameter static var isPerforming: Bool = false
        /// The Welcome flow or the consent sheet is up.
        @Parameter static var isOnboarding: Bool = false
        @Parameter static var isWhatsNewShowing: Bool = false

        // MARK: Per-tip parameters

        @Parameter static var librarySongCount: Int = 0
        @Parameter static var openSetlistHasEntries: Bool = false
        @Parameter static var gigModeConfigured: Bool = false

        // swiftformat:enable redundantType propertyTypes

        // MARK: Events

        static let searched = Tips.Event(id: "searched")
        static let songViewed = Tips.Event(id: "songViewed")
        static let visualEditorOpened = Tips.Event(id: "visualEditorOpened")
        static let showStarted = Tips.Event(id: "showStarted")
        /// A song reached the paste review sheet (P3-4).
        static let pasteReviewed = Tips.Event(id: "pasteReviewed")

        @MainActor
        static func donate(_ event: Tips.Event<Tips.EmptyDonation>) {
            Task { await event.donate() }
        }

        /// Transpose or capo changed in the song view.
        @MainActor
        static func transposeChanged() {
            TransposeViewTip().invalidate(reason: .actionPerformed)
        }

        /// A chord was dragged to another syllable in the canvas.
        @MainActor
        static func chordMoved() {
            MoveChordTip().invalidate(reason: .actionPerformed)
        }

        // MARK: Launch

        /// Once at launch, before any tip view exists. A pending reset (Settings > Data) or a
        /// reset test launch clears the datastore first. Test runs keep their own datastore
        /// and hide every tip unless `-SegueTips show`, which applies the real rules with no
        /// daily limit.
        @MainActor
        public static func configure(
            launch: PolishLaunch,
            preferences: PolishPreferences,
        ) {
            let location: Tips.ConfigurationOption.DatastoreLocation = if launch.isTestRun {
                .url(URL.applicationSupportDirectory.appending(
                    path: "TipKit-uitest",
                    directoryHint: .isDirectory,
                ))
            } else {
                .applicationDefault
            }
            if preferences.tipsResetPending || launch.resetTips || launch.tips == .show {
                try? Tips.resetDatastore()
                preferences.clearTipsReset()
            }
            if launch.tips == .hide {
                Tips.hideAllTipsForTesting()
            }
            let frequency: Tips.ConfigurationOption.DisplayFrequency =
                launch.tips == .show ? .immediate : .daily
            try? Tips.configure([.displayFrequency(frequency), .datastoreLocation(location)])
        }
    }

    /// The rules every tip shares.
    private extension Tip {
        static var globalRules: [Tips.Rule] {
            [
                #Rule(SegueTips.$isPerforming) { $0 == false },
                #Rule(SegueTips.$isOnboarding) { $0 == false },
                #Rule(SegueTips.$isWhatsNewShowing) { $0 == false },
            ]
        }
    }

    /// Popover on the library search field.
    struct SearchAnyLineTip: Tip {
        /// The guide page its Learn More opens (WS6 7.2).
        static let guidePage: SegueLinks.Guide = .search

        var title: Text {
            Text("Search by any line")
        }

        var message: Text? {
            Text("Search by any line you remember. Spellings like pyar and pyaar find the "
                + "same song.")
        }

        var actions: [Tips.Action] {
            [GuideTipAction.action]
        }

        var rules: [Tips.Rule] {
            Self.globalRules + [
                #Rule(SegueTips.$librarySongCount) { $0 >= 5 },
                #Rule(SegueTips.searched) { $0.donations.count == 0 },
            ]
        }
    }

    /// Popover on the song list's New Song button (P3-4): New Song from Clipboard.
    struct PasteSongTip: Tip {
        /// The guide page its Learn More opens (WS6 7.2).
        static let guidePage: SegueLinks.Guide = .pasteASong

        var title: Text {
            Text("Paste any chord sheet")
        }

        var message: Text? {
            Text("Copy a song from a chord site or a note and press ⌥⌘V. Segue turns it into "
                + "a song for you to check, right here on your Mac.")
        }

        var actions: [Tips.Action] {
            [GuideTipAction.action]
        }

        var rules: [Tips.Rule] {
            Self.globalRules + [#Rule(SegueTips.pasteReviewed) { $0.donations.count == 0 }]
        }
    }

    /// Popover on the song view's transpose control.
    struct TransposeViewTip: Tip {
        /// The guide page its Learn More opens (WS6 7.2).
        static let guidePage: SegueLinks.Guide = .transpose

        var title: Text {
            Text("Change the key for this view")
        }

        var message: Text? {
            Text("Change the key or capo for this view without touching the file.")
        }

        var actions: [Tips.Action] {
            [GuideTipAction.action]
        }

        var rules: [Tips.Rule] {
            Self.globalRules + [#Rule(SegueTips.songViewed) { $0.donations.count >= 3 }]
        }
    }

    /// Inline above the visual editor canvas.
    struct MoveChordTip: Tip {
        /// The guide page its Learn More opens (WS6 7.2).
        static let guidePage: SegueLinks.Guide = .moveChord

        var title: Text {
            Text("Move a chord")
        }

        var message: Text? {
            Text("Drag a chord onto another syllable to move it.")
        }

        var actions: [Tips.Action] {
            [GuideTipAction.action]
        }

        var rules: [Tips.Rule] {
            Self.globalRules + [#Rule(SegueTips.visualEditorOpened) { $0.donations.count >= 1 }]
        }
    }

    /// Popover on the builder's Start Show button.
    struct StartShowTip: Tip {
        /// The guide page its Learn More opens (WS6 7.2).
        static let guidePage: SegueLinks.Guide = .goOnStage

        var title: Text {
            Text("Start the show")
        }

        var message: Text? {
            Text("Start Show goes full screen and dark. Press ? on stage to see every key.")
        }

        var actions: [Tips.Action] {
            [GuideTipAction.action]
        }

        var rules: [Tips.Rule] {
            Self.globalRules + [
                #Rule(SegueTips.$openSetlistHasEntries) { $0 == true },
                #Rule(SegueTips.showStarted) { $0.donations.count == 0 },
            ]
        }
    }

    /// Inline at the top of the setlist builder: the only discovery path for Gig Mode (A37).
    struct GigModeTip: Tip {
        static let openSettingsAction = "openSettings"

        /// The guide page its Learn More opens (WS6 7.2).
        static let guidePage: SegueLinks.Guide = .gigMode

        var title: Text {
            Text("Gig Mode")
        }

        var message: Text? {
            Text("Silence notifications while you play: set up Gig Mode Shortcuts in "
                + "Settings > Live.")
        }

        var actions: [Tips.Action] {
            [
                Tips.Action(id: Self.openSettingsAction, title: "Open Settings"),
                GuideTipAction.action,
            ]
        }

        var rules: [Tips.Rule] {
            Self.globalRules + [
                #Rule(SegueTips.showStarted) { $0.donations.count >= 1 },
                #Rule(SegueTips.$gigModeConfigured) { $0 == false },
            ]
        }
    }
#endif
