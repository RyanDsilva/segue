#if os(macOS)
    import Foundation
    import Observation

    /// The Welcome sheet's state (WS2b 4.1): which pages this flow has, which one is up, and
    /// the in-page state (checkbox, seeding, errors). The flow logic that moves it lives in
    /// `AppModel+Onboarding.swift`; the sheet only reads it and calls the model's actions.
    @MainActor
    @Observable
    public final class OnboardingModel {
        public enum Page: Equatable, Sendable {
            /// "Where should your songs live?"
            case library
            /// "Welcome to Segue": the cards and the Welcome songs checkbox.
            case welcomeSongs
            /// "Help improve Segue?": WS3's `ConsentChoiceView`.
            case consent
        }

        public enum Mode: Equatable, Sendable {
            /// The first-run flow (new install, or resuming one that was not finished).
            case flow
            /// Help > Welcome to Segue…: the cards and "Add Welcome Songs", dismissable.
            case revisit
        }

        /// Seeding on page 2 (or "Add Welcome Songs" in revisit mode).
        public enum SeedState: Equatable, Sendable {
            case idle
            case seeding
            /// "Segue could not add the Welcome songs (reason)."
            case failed(String)
        }

        /// nil: the sheet is not up.
        public internal(set) var mode: Mode?
        /// The pages of this flow, in order ("Step n of m" counts them).
        public internal(set) var pages: [Page] = []
        public internal(set) var page: Page = .library

        /// Page 2's checkbox: on for an empty library, off when it already has songs (A13).
        public var addsWelcomeSongs = true
        public internal(set) var seedState: SeedState = .idle
        /// Page 1: why the folder could not be opened (the chooser's `openFailed` text).
        public internal(set) var libraryError: String?
        /// Revisit mode: a Welcome-tagged song is in the open library.
        public internal(set) var hasWelcomeSongs = false
        /// Page 1: the open or save panel is up (both buttons wait).
        public internal(set) var isChoosingFolder = false

        public init() {}

        /// The first-run flow is up: WS3's standalone consent sheet stays away meanwhile (I-1).
        public var isPresentingWelcome: Bool {
            mode == .flow
        }

        /// "Step n of m" for the flow; nil in revisit mode.
        public var stepLabel: String? {
            guard mode == .flow, let index = pages.firstIndex(of: page) else { return nil }
            return "Step \(index + 1) of \(pages.count)"
        }

        func begin(_ pages: [Page], at page: Page) {
            self.pages = pages
            self.page = page
            seedState = .idle
            libraryError = nil
            mode = .flow
        }

        func beginRevisit(hasWelcomeSongs: Bool) {
            pages = [.welcomeSongs]
            page = .welcomeSongs
            seedState = .idle
            self.hasWelcomeSongs = hasWelcomeSongs
            mode = .revisit
        }

        func close() {
            mode = nil
            seedState = .idle
            libraryError = nil
        }
    }
#endif
