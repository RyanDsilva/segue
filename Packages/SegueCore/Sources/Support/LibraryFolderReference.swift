import Foundation

/// How a library folder is recognised across opens (R185, P9-6 5.2): its file identifier
/// and a security-scoped bookmark, both kept in `state.json`.
///
/// The identifier is `URLResourceValues.fileIdentifier` (the inode, macOS 13.3+), not
/// `fileResourceIdentifier`: Apple documents the latter as not persistent across restarts,
/// which would make every reboot look like a changed folder. A Finder copy gets a new
/// identifier; a move or rename on the same volume keeps it; a move to another volume
/// changes it, and then the bookmark tells the two apart (the original is gone).
public enum LibraryFolderReference {
    /// The folder's file identifier; nil when it cannot be read.
    public static func identifier(of url: URL) -> UInt64? {
        (try? url.resourceValues(forKeys: [.fileIdentifierKey]))?.fileIdentifier
    }

    /// A security-scoped bookmark to the folder (the app-scope bookmarks entitlement);
    /// nil when it cannot be made.
    public static func bookmark(of url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        )
    }

    /// Runs `body` on the folder `bookmark` resolves to, inside its security scope; nil
    /// when the bookmark no longer resolves to an existing folder.
    public static func withResolved<T>(_ bookmark: Data, _ body: (URL) -> T) -> T? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        ) else { return nil }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory,
        ), isDirectory.boolValue else { return nil }
        return body(url)
    }
}
