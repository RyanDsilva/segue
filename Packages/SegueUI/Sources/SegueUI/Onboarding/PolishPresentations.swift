#if os(macOS)
    import SwiftUI

    public extension View {
        /// WS2b's sheets over the main window: the Welcome sheet (first run, resume, revisit)
        /// and What's New.
        func polishPresentations(_ app: AppModel) -> some View {
            modifier(PolishPresentations(app: app))
        }
    }

    extension AppModel {
        /// Nothing of higher launch priority is up (4.1 ordering: the resume prompt, the
        /// pre-show checklist, reorder reviews and the start-failure alert come first), and
        /// no show is on stage or starting.
        var launchUIIsClear: Bool {
            !isPerforming && !isStartingShow && pendingResume == nil && preShow == nil
                && pendingReorderReviews.isEmpty && startFailure == nil
        }

        /// The Welcome sheet is on screen now.
        var showsWelcomeSheet: Bool {
            guard onboarding.mode != nil, launchUIIsClear else { return false }
            return switch state {
            case .ready: true
            // Page 1 sits over the wordmark until the library opens.
            case .needsLibrary, .opening: onboarding.mode == .flow
            case .starting: false
            }
        }
    }

    struct PolishPresentations: ViewModifier {
        let app: AppModel

        func body(content: Content) -> some View {
            let showsWelcome = app.showsWelcomeSheet
            let showsWhatsNew = app.showsWhatsNewSheet
            let onboarding = showsWelcome || app.showsConsentPrompt
            content
                // Tips stay away from every launch sheet (WS2b 4.4).
                .onChange(of: onboarding, initial: true) { _, value in
                    SegueTips.isOnboarding = value
                }
                .onChange(of: showsWhatsNew, initial: true) { _, value in
                    SegueTips.isWhatsNewShowing = value
                }
                .background {
                    Color.clear.sheet(isPresented: .constant(showsWelcome)) {
                        WelcomeSheet(app: app, model: app.onboarding)
                    }
                }
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { showsWhatsNew },
                        set: {
                            if !$0 {
                                app.dismissWhatsNew()
                            }
                        },
                    )) {
                        if let content = app.whatsNew {
                            WhatsNewSheet(
                                content: content,
                                workspace: app.dependencies.workspace,
                                onDismiss: { app.dismissWhatsNew() },
                            )
                        }
                    }
                }
        }
    }
#endif
