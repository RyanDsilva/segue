#if os(macOS)
    import AppKit
    import StoreKit
    import SwiftUI

    extension View {
        /// The main window fires an armed review prompt (WS2b 4.5): only here, never from a
        /// button and never in the stage window.
        func reviewPromptTrigger(_ app: AppModel) -> some View {
            modifier(ReviewPromptTrigger(app: app))
        }
    }

    /// Watches an armed prompt and fires it once the main window has been key for 3
    /// continuous seconds with nothing else going on.
    private struct ReviewPromptTrigger: ViewModifier {
        let app: AppModel
        @Environment(\.requestReview) private var requestReview

        func body(content: Content) -> some View {
            content.task(id: app.reviewPromptPending) {
                guard app.reviewPromptPending else { return }
                var keySince: ContinuousClock.Instant?
                while app.reviewPromptPending, !Task.isCancelled {
                    let now = ContinuousClock.now
                    if Self.mainWindowIsKey {
                        keySince = keySince ?? now
                    } else {
                        keySince = nil
                    }
                    let keyFor = keySince.map { now - $0 } ?? .zero
                    if ReviewPromptPolicy.mayFire(app.reviewMoment(keyFor: keyFor)) {
                        app.fireReviewPrompt(using: requestReview)
                        return
                    }
                    if !ReviewPromptPolicy.mayFire(app.reviewMoment(keyFor: .seconds(60))) {
                        // Something else is up: the 3 seconds start again afterwards.
                        keySince = nil
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }

        /// The key window is the main library window (not Settings, not the stage).
        private static var mainWindowIsKey: Bool {
            guard let key = NSApp.keyWindow else { return false }
            return key.identifier?.rawValue.hasPrefix(SegueRootView.windowID) == true
        }
    }
#endif
