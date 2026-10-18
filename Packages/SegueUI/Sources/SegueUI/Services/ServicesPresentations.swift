#if os(macOS)
    import SwiftUI

    extension AppModel {
        /// Whether WS2b's Welcome flow is on screen (it then hosts the consent choice as its
        /// last page), so the standalone `ConsentSheet` stays away (WS3 spec 4.4, I-1).
        var isPresentingWelcome: Bool {
            onboarding.isPresentingWelcome
        }

        /// The consent prompt is due and nothing else is in the way (spec 4.2 step 2, 4.4):
        /// the library state has settled, no show is on stage or starting, and no other
        /// launch prompt (resume, checklist, reorder review, start failure) is up.
        var showsConsentPrompt: Bool {
            guard dependencies.consent.needsPrompt, !isPresentingWelcome, !isPerforming,
                  !dependencies.reportPresenter.isShowing,
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
        /// What the services present over the main window: the consent prompt and Report a
        /// Problem.
        func servicesPresentations(_ app: AppModel) -> some View {
            modifier(ServicesPresentations(app: app))
        }
    }

    struct ServicesPresentations: ViewModifier {
        let app: AppModel
        @State private var report: ReportProblemModel?
        /// The window's size, so the report sheet never runs past a small window.
        @State private var hostSize: CGSize = .zero

        func body(content: Content) -> some View {
            // Read here, in the body, so observation re-evaluates them.
            let showsConsent = app.showsConsentPrompt
            let presenter = app.dependencies.reportPresenter
            let showsReport = presenter.isPresented && !app.isPerforming && !showsConsent
            content
                .onGeometryChange(for: CGSize.self) { $0.size } action: { hostSize = $0 }
                .background {
                    Color.clear.sheet(isPresented: .constant(showsConsent)) {
                        ConsentSheet(
                            store: app.dependencies.consent,
                            workspace: app.dependencies.workspace,
                        )
                    }
                }
                .background {
                    Color.clear.sheet(isPresented: Binding(
                        get: { showsReport },
                        set: {
                            if !$0 {
                                presenter.dismiss()
                            }
                        },
                    )) {
                        if let report {
                            ReportProblemSheet(
                                model: report,
                                workspace: app.dependencies.workspace,
                                onRequestFeature: {
                                    presenter.dismiss()
                                    app.requestFeature()
                                },
                                onClose: { presenter.dismiss() },
                                height: ReportProblemSheet.height(fitting: hostSize),
                            )
                            .onAppear { presenter.isShowing = true }
                            .onDisappear { presenter.isShowing = false }
                        }
                    }
                }
                .onChange(of: presenter.isPresented, initial: true) { _, isPresented in
                    // A fresh form every time: the song file is off again (R22).
                    report = isPresented ? app.makeReportModel() : nil
                }
        }
    }
#endif
