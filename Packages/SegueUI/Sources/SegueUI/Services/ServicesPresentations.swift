#if os(macOS)
    import SwiftUI

    extension AppModel {
        /// Whether WS2b's Welcome flow is on screen (it then hosts the consent choice as its
        /// last page). WS2b replaces this with its model's state; until then the standalone
        /// `ConsentSheet` covers first run too (WS3 spec 4.4).
        var isPresentingWelcome: Bool {
            false
        }

        /// The consent prompt is due and nothing else is in the way (spec 4.2 step 2, 4.4):
        /// the library state has settled, no show is on stage or starting, and no other
        /// launch prompt (resume, checklist, reorder review, start failure) is up.
        var showsConsentPrompt: Bool {
            guard dependencies.consent.needsPrompt, !isPresentingWelcome, !isPerforming,
                  !isStartingShow, pendingResume == nil, preShow == nil,
                  pendingReorderReviews.isEmpty, startFailure == nil
            else {
                return false
            }
            return switch state {
            case .needsLibrary, .ready: true
            case .opening, .starting: false
            }
        }
    }

    public extension View {
        /// What the services present over the main window: the consent prompt.
        func servicesPresentations(_ app: AppModel) -> some View {
            modifier(ServicesPresentations(app: app))
        }
    }

    struct ServicesPresentations: ViewModifier {
        let app: AppModel

        func body(content: Content) -> some View {
            // Read here, in the body, so observation re-evaluates it.
            let showsConsent = app.showsConsentPrompt
            content
                .background {
                    Color.clear.sheet(isPresented: .constant(showsConsent)) {
                        ConsentSheet(
                            store: app.dependencies.consent,
                            workspace: app.dependencies.workspace,
                        )
                    }
                }
        }
    }
#endif
