import Foundation
@testable import SegueUI
import Shows
import Testing

/// The review prompt's rules (WS2b 4.5, R20, A12) as a table, plus the counting through the
/// app: only gigs count, the 1st arms it, once per version, never when quitting.
@MainActor
struct ReviewPromptPolicyTests {
    struct ArmCase: Sendable, CustomStringConvertible {
        var gigs: Int
        var lastRequested: String?
        var current: String
        var quitting = false
        var arms: Bool

        var description: String {
            "\(gigs) gigs, last \(lastRequested ?? "none"), now \(current), quit \(quitting)"
        }
    }

    @Test(arguments: [
        ArmCase(gigs: 0, lastRequested: nil, current: "0.5", arms: false),
        ArmCase(gigs: 1, lastRequested: nil, current: "0.5", arms: true),
        ArmCase(gigs: 2, lastRequested: nil, current: "0.5", arms: true),
        ArmCase(gigs: 1, lastRequested: "0.5", current: "0.5", arms: false),
        ArmCase(gigs: 3, lastRequested: "0.5.0", current: "0.5", arms: false),
        ArmCase(gigs: 1, lastRequested: "0.5", current: "0.6", arms: true),
        ArmCase(gigs: 1, lastRequested: nil, current: "0.5", quitting: true, arms: false),
    ])
    func `when a completed gig arms the prompt`(_ row: ArmCase) {
        #expect(ReviewPromptPolicy.arms(
            completedGigs: row.gigs,
            lastRequestedVersion: row.lastRequested,
            currentVersion: row.current,
            quitsAfterEnding: row.quitting,
        ) == row.arms)
    }

    @Test
    func `it fires only when the main window is quiet for three seconds`() {
        var clear = ReviewPromptPolicy.Moment()
        clear.keyFor = .seconds(3)
        #expect(ReviewPromptPolicy.mayFire(clear))
        var early = clear
        early.keyFor = .milliseconds(2900)
        #expect(!ReviewPromptPolicy.mayFire(early))
        let blockers: [WritableKeyPath<ReviewPromptPolicy.Moment, Bool>] = [
            \.isPerforming, \.stageWindowOpen, \.isStartingShow, \.resumePending,
            \.checklistUp, \.reorderReviewsPending, \.otherPresentation, \.errorBannerShown,
        ]
        for blocker in blockers {
            var moment = clear
            moment[keyPath: blocker] = true
            #expect(!ReviewPromptPolicy.mayFire(moment), "\(blocker)")
        }
    }

    @Test
    func `only gigs count and the prompt is once per version`() throws {
        let env = try TestEnvironment()
        let app = env.app()
        app.countCompletedShow(kind: .rehearsal, quitsAfterEnding: false)
        #expect(app.polish.review.completedGigs == 0)
        #expect(!app.reviewPromptPending)

        app.countCompletedShow(kind: .gig, quitsAfterEnding: false)
        #expect(app.polish.review.completedGigs == 1)
        #expect(app.reviewPromptPending)

        // Requested in this version: the next gig does not arm it again.
        app.polish.review.markRequested(version: app.polish.appVersion)
        app.reviewPromptPending = false
        app.countCompletedShow(kind: .gig, quitsAfterEnding: false)
        #expect(app.polish.review.completedGigs == 2)
        #expect(!app.reviewPromptPending)
    }
}
