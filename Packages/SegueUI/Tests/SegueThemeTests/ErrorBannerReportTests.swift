import Foundation
@testable import SegueUI
import Testing

/// P9-5 section 5 (P1): the error banner's Report... opens Report a Problem with what the
/// banner said, and never while a show is up.
@MainActor
struct ErrorBannerReportTests {
    @Test
    func `report on the banner opens the form with the error in the message`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let presenter = app.dependencies.reportPresenter
        let banner = "The song was changed in another app since you opened it. Nothing was saved."

        app.reportBannerError(banner)
        #expect(presenter.isPresented)
        #expect(presenter.prefill.contains(banner))
        let model = app.makeReportModel(message: presenter.prefill)
        #expect(model.message.hasPrefix("Segue showed this error: \(banner)"))

        // Closing it leaves Help > Report a Problem's next form empty.
        presenter.dismiss()
        presenter.present()
        #expect(presenter.prefill.isEmpty)
        #expect(app.makeReportModel(message: presenter.prefill).message.isEmpty)
        presenter.dismiss()
    }

    @Test
    func `report on the banner does nothing while a show is starting`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        app.isStartingShow = true
        app.reportBannerError("Could not redo the import.")
        #expect(!app.dependencies.reportPresenter.isPresented)
        app.isStartingShow = false
    }
}
