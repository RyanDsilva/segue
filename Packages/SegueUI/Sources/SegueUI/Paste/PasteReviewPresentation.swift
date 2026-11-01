#if os(macOS)
    import Library
    import SwiftUI

    extension View {
        /// Presents the paste review sheet while the library has one open (P3-4).
        func pasteReviewSheet(app: AppModel, session: LibrarySession) -> some View {
            modifier(PasteReviewPresentation(app: app, session: session))
        }
    }

    private struct PasteReviewPresentation: ViewModifier {
        let app: AppModel
        let session: LibrarySession
        @Environment(\.openSettings) private var openSettings

        private var library: LibraryViewModel {
            session.library
        }

        func body(content: Content) -> some View {
            content
                .sheet(isPresented: isPresented) {
                    if let review = library.pasteReview {
                        PasteReviewSheet(review: review, context: context)
                            .task { await app.ai.refreshAvailability() }
                    }
                }
        }

        private var isPresented: Binding<Bool> {
            Binding(
                get: { library.pasteReview != nil },
                set: { shown in
                    if !shown, library.pasteReview != nil {
                        Task { await library.cancelPasteReview() }
                    }
                },
            )
        }

        private var context: PasteReviewContext {
            PasteReviewContext(
                aiEnabled: app.ai.gate.isEnabled,
                availability: app.ai.availability,
                suggestsDownload: app.ai.models.suggestsDownload,
                knownArtists: library.knownArtists,
                knownAlbums: library.knownAlbums,
                knownTags: library.tags.map(\.tag),
                accept: { Task { await library.acceptPasteReview() } },
                cancel: { Task { await library.cancelPasteReview() } },
                startBlank: { library.startBlank() },
                openAISettings: {
                    app.selectAISettingsPane()
                    openSettings()
                },
                openSystemSettings: {
                    AIAvailabilityCopy.openSettings(with: app.dependencies.workspace)
                },
            )
        }
    }
#endif
