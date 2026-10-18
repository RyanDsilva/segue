#if os(macOS)
    import AppKit
    import Shows
    import StoreKit
    import SwiftUI

    // WS2b 4.5 (R20, A12): count completed gigs, arm the prompt after the 1st, fire it from
    // the main window once the end-of-show flow is done. Never at launch, never on stage.

    extension AppModel {
        /// A gig ended in this session or from the resume prompt (rehearsals and gigs closed
        /// stale at launch never count): count it and maybe arm the prompt.
        func countCompletedShow(kind: ShowKind, quitsAfterEnding: Bool) {
            guard kind == .gig else { return }
            let review = polish.review
            review.recordCompletedGig()
            if ReviewPromptPolicy.arms(
                completedGigs: review.completedGigs,
                lastRequestedVersion: review.lastRequestedVersion,
                currentVersion: polish.appVersion,
                quitsAfterEnding: quitsAfterEnding,
            ) {
                reviewPromptPending = true
            }
        }

        /// What the main window sees now, for `ReviewPromptPolicy.mayFire`.
        func reviewMoment(keyFor: Duration) -> ReviewPromptPolicy.Moment {
            var moment = ReviewPromptPolicy.Moment()
            moment.isPerforming = isPerforming
            moment.stageWindowOpen = StageWindowController.shared.stageWindow != nil
            moment.isStartingShow = isStartingShow
            moment.resumePending = pendingResume != nil
            moment.checklistUp = preShow != nil
            moment.reorderReviewsPending = !pendingReorderReviews.isEmpty
            let library = session?.library
            moment.otherPresentation = showsWelcomeSheet || showsWhatsNewSheet
                || showsConsentPrompt || dependencies.reportPresenter.isPresented
                || startFailure != nil || session?.songTrashConfirmation != nil
                || library?.pendingNavigation != nil || session?.isNamingNewSetlist == true
            moment.errorBannerShown = library?.errorMessage != nil
                || session?.setlists.errorMessage != nil || session?.gigLog.errorMessage != nil
            moment.keyFor = keyFor
            return moment
        }

        /// Asks for the review (or logs it in tests) and records the version.
        func fireReviewPrompt(using action: RequestReviewAction) {
            guard reviewPromptPending else { return }
            reviewPromptPending = false
            polish.reviewRequester.requestReview(using: action)
            polish.review.markRequested(version: polish.appVersion)
        }
    }
#endif
