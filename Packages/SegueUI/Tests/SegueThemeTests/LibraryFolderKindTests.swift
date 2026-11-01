import AppKit
import Foundation
@testable import SegueUI
import SwiftUI
import Testing

/// File-sync folder detection and the warning's lifecycle (P9-6 5.4).
@MainActor
struct LibraryFolderKindTests {
    private static let home = URL(filePath: "/Users/ryan", directoryHint: .isDirectory)

    @Test(arguments: [
        ("/Users/ryan/Music/Segue", false, LibraryFolderKind.local),
        ("/Users/ryan/Desktop/Segue", true, .iCloudDrive),
        ("/Users/ryan/Library/Mobile Documents/com~apple~CloudDocs/Segue", false, .iCloudDrive),
        ("/Users/ryan/Library/CloudStorage/Dropbox/Segue", false, .fileProvider("Dropbox")),
        (
            "/Users/ryan/Library/CloudStorage/Dropbox-Personal/Music",
            false,
            .fileProvider("Dropbox"),
        ),
        (
            "/Users/ryan/Library/CloudStorage/GoogleDrive-ryan@example.com/My Drive/Segue",
            false,
            .fileProvider("Google Drive"),
        ),
        (
            "/Users/ryan/Library/CloudStorage/OneDrive-Personal/Segue",
            false,
            .fileProvider("OneDrive"),
        ),
        ("/Users/ryan/Library/CloudStorage/Box-Box/Segue", false, .fileProvider("Box")),
        ("/Users/ryan/Library/CloudStorage/SomeDrive-x/Segue", false, .fileProvider("SomeDrive")),
        ("/Users/ryan/Library/CloudStorageNotes/Segue", false, .local),
        ("/Volumes/Gig/Segue", false, .local),
    ])
    func `detects the folder kind from its path and resource value`(
        path: String,
        ubiquitous: Bool,
        expected: LibraryFolderKind,
    ) {
        let kind = LibraryFolderKind.detect(
            URL(filePath: path, directoryHint: .isDirectory),
            home: Self.home,
            isUbiquitous: { _ in ubiquitous },
        )
        #expect(kind == expected)
    }

    @Test
    func `the warning names the service and never the account`() {
        #expect(LibraryFolderKind.local.warning == nil)
        #expect(LibraryFolderKind.iCloudDrive.warningTitle == "This library is in iCloud Drive.")
        let google = LibraryFolderKind.detect(
            URL(filePath: "/Users/ryan/Library/CloudStorage/GoogleDrive-ryan@example.com/x"),
            home: Self.home,
            isUbiquitous: { _ in nil },
        )
        #expect(google.warning?.hasPrefix("This library is in Google Drive. Files there") == true)
        #expect(google.warning?.contains("example.com") == false)
    }

    @Test
    func `the banner shows until Don't Show Again, remembered for the library`() async throws {
        let env = try TestEnvironment()
        env.folderKind = .fileProvider("Dropbox")
        // Two app instances on one library in turn (a relaunch), without contending.
        env.libraryLock = .unlocked
        let app = try await env.openApp()
        let session = try #require(app.session)
        #expect(session.showsFileSyncWarning)
        session.library.isPerforming = true
        #expect(!session.showsFileSyncWarning, "never during a show")
        session.library.isPerforming = false

        session.dismissFileSyncWarning()
        #expect(!session.showsFileSyncWarning)
        #expect(session.folderKind.warning != nil, "Settings > Data still says it")

        // Another launch on the same library: still dismissed.
        let relaunched = try await env.openApp()
        #expect(relaunched.session?.folderKind == .fileProvider("Dropbox"))
        #expect(relaunched.session?.showsFileSyncWarning == false)
    }

    @Test
    func `a local library shows no warning`() async throws {
        let env = try TestEnvironment()
        let app = try await env.openApp()
        #expect(app.session?.folderKind == .local)
        #expect(app.session?.showsFileSyncWarning == false)
    }

    /// The banner over the real song list, light and dark, to
    /// `.build/screenshots/file-sync/` (hosted off screen, so AppKit controls draw as in the
    /// app).
    @Test
    func `the banner renders at the top of the library list`() async throws {
        let env = try TestEnvironment()
        try FileManager.default.createDirectory(
            at: env.libraryURL.appending(path: "songs", directoryHint: .isDirectory),
            withIntermediateDirectories: true,
        )
        try env.write("{title: Harbour Lights}\n{key: G}\n[G]Lights\n", to: "songs/harbour.cho")
        try env.write("{title: River Song}\n{key: D}\n[D]River\n", to: "songs/river.cho")
        env.folderKind = .iCloudDrive
        let app = try await env.openApp()
        let session = try #require(app.session)
        for dark in [false, true] {
            let list = SongListView(model: session.library, session: session)
                .environment(\.openGuide, OpenGuideAction { _ in })
                .frame(width: 380, height: 420)
            let host = NSHostingView(rootView: list)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 380, height: 420)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let image = try #require(rep.cgImage)
            try DiagramSnapshotTests.writePNG(
                image,
                to: DiagramSnapshotTests.screenshotDirectory
                    .deletingLastPathComponent()
                    .appending(path: "file-sync/banner-\(dark ? "dark" : "light").png"),
            )
        }
    }
}
