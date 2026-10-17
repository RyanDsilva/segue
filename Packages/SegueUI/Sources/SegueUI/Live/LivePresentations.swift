// Phase 2 frozen interface (docs/phases/2-interfaces.md). Owner: unit C.

#if os(macOS)
    import Shows
    import SwiftUI

    public extension View {
        /// Everything live mode presents over the main window: the pre-show checklist (with
        /// the missing-songs warning), "Resume show?", the "could not start" alert and the
        /// show-end reorder review (`ReorderDiffSheet`, unit D's view, for
        /// `app.pendingReorderReviews.first`). The main window applies this once, so unit C
        /// never edits the root view.
        func liveModePresentations(_ app: AppModel) -> some View {
            modifier(LiveModePresentations(app: app))
        }
    }

    struct LiveModePresentations: ViewModifier {
        let app: AppModel

        func body(content: Content) -> some View {
            content
                .background { checklistHost }
                .background { reviewHost }
                .alert(
                    resumeTitle,
                    isPresented: isAsking(app.pendingResume != nil && !app.isPerforming),
                    presenting: app.pendingResume,
                ) { _ in
                    Button("Resume") { Task { await app.resumePendingShow() } }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier(AccessibilityID.resumeShowResume)
                    Button("End Show") { Task { await app.endPendingShow() } }
                        .accessibilityIdentifier(AccessibilityID.resumeShowEnd)
                } message: { record in
                    Text(resumeMessage(record))
                }
                .alert(
                    "The show did not start",
                    isPresented: isAsking(app.startFailure != nil) { app.dismissStartFailure() },
                    presenting: app.startFailure,
                ) { _ in
                    Button("OK", role: .cancel) { app.dismissStartFailure() }
                } message: { message in
                    Text(message)
                }
        }

        private var checklistHost: some View {
            Color.clear.sheet(item: checklistBinding) { checklist in
                PreShowChecklistView(checklist: checklist)
                    .interactiveDismissDisabled()
            }
        }

        private var reviewHost: some View {
            Color.clear.sheet(isPresented: isAsking(showsReview)) {
                if let diff = app.pendingReorderReviews.first {
                    ReorderDiffSheet(
                        diff: diff,
                        onSave: { inserted in
                            Task { await app.resolveReorderReview(save: true, including: inserted) }
                        },
                        onDiscard: {
                            Task { await app.resolveReorderReview(save: false, including: []) }
                        },
                    )
                    .interactiveDismissDisabled()
                    .id(diff.setlistId.description + "\(app.pendingReorderReviews.count)")
                }
            }
        }

        /// Reviews wait until the stage and the checklist are gone.
        private var showsReview: Bool {
            !app.pendingReorderReviews.isEmpty && !app.isPerforming && app.preShow == nil
                && app.pendingResume == nil
        }

        private var checklistBinding: Binding<PreShowChecklist?> {
            Binding(
                get: { app.preShow },
                set: { value in
                    if value == nil {
                        app.preShow?.answer(false)
                    }
                },
            )
        }

        /// A presentation binding that cannot be dismissed except through its buttons.
        private func isAsking(
            _ value: Bool,
            onDismiss: @escaping () -> Void = {},
        ) -> Binding<Bool> {
            Binding(get: { value }, set: { presented in
                if !presented {
                    onDismiss()
                }
            })
        }

        private var resumeTitle: String {
            guard let record = app.pendingResume else { return "" }
            return record.kind == .gig ? "Resume “\(record.setlistName)”?"
                : "Resume the rehearsal of “\(record.setlistName)”?"
        }

        private func resumeMessage(_ record: ShowRecord) -> String {
            let song = record.currentItem.map { "at “\($0.title)”" } ?? "at the end of the set"
            let time = record.updatedAt.formatted(date: .omitted, time: .shortened)
            let ending = record.kind == .gig ? "End Show closes it into the gig log."
                : "End closes it; rehearsals never go in the gig log."
            return "It stopped \(song) at \(time). Resume picks up at the same song and "
                + "scroll position. \(ending)"
        }
    }
#endif
