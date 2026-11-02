import Foundation
import Library
@testable import SegueUI
import Support
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

        app.reportBannerError(banner, code: .saveConflict)
        #expect(presenter.isPresented)
        #expect(presenter.prefill.contains(banner))
        let model = app.makeReportModel(message: presenter.prefill)
        #expect(model.message.hasPrefix("Segue showed this error (saveConflict): \(banner)"))

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
        app.reportBannerError("Could not redo the import.", code: .importFailed)
        #expect(!app.dependencies.reportPresenter.isPresented)
        app.isStartingShow = false
    }

    @Test
    func `a banner error carries its code until it is dismissed`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        let library = try #require(app.session?.library)
        let id = try SongID(#require(ULID(string: "01JC0000000000000000000H01")))
        library.pendingErrorCode = UserMessage.code(
            for: LibraryError.conflict(id, .sourceChanged),
            else: .saveFailed,
        )
        library.errorMessage = "The song was changed in another app."
        #expect(library.errorCode == .saveConflict)
        library.errorMessage = "Something else."
        #expect(library.errorCode == .other, "a message set without a code is other")
        library.errorMessage = nil
        #expect(library.errorCode == nil)
        #expect(UserMessage
            .code(for: LibraryError.notOpen, else: .saveFailed) == .libraryOpenFailed)
        #expect(UserMessage
            .code(for: CocoaError(.fileNoSuchFile), else: .importFailed) == .importFailed)
    }
}
