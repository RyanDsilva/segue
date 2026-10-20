import Foundation
import ModelPort

/// Where downloaded models live (spec 5.3, R67, R100): `<root>/<repo>/<revision>/`, with
/// `<root>` = `<app-group container>/Library/Application Support/Models` in the app, shared by
/// both flavours, excluded from backup, never inside the library folder or its archive.
public struct ModelStoreLocation: Sendable, Hashable {
    /// The team-prefixed app group both flavours share (no portal registration, R100).
    public static let appGroupID = "V6BM673U35.dev.ryandsilva.segue.models"

    /// The marker written once every file of a model is verified.
    static let installMarker = ".segue-installed.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The shared store in the app-group container, or nil when the container is not
    /// reachable (a build without the entitlement, or command-line tools).
    public static func appGroup(fileManager: FileManager = .default) -> Self? {
        guard let group = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID,
        ) else { return nil }
        // macOS always returns a URL; whether the sandbox lets us in shows on first use.
        return Self(root: group.appending(
            path: "Library/Application Support/Models",
            directoryHint: .isDirectory,
        ))
    }

    /// `<root>/<repo>/<revision>/`.
    public func modelDirectory(for model: LocalModelManifest) -> URL {
        root.appending(path: model.repo, directoryHint: .isDirectory)
            .appending(path: model.revision, directoryHint: .isDirectory)
    }

    /// `<root>/.partial/<repo>/<revision>/`: files still downloading (kept on Cancel, so
    /// Download resumes them).
    func partialDirectory(for model: LocalModelManifest) -> URL {
        root.appending(path: ".partial", directoryHint: .isDirectory)
            .appending(path: model.repo, directoryHint: .isDirectory)
            .appending(path: model.revision, directoryHint: .isDirectory)
    }

    /// The cross-flavour download lock.
    var lockURL: URL {
        root.appending(path: ".download.lock")
    }

    /// Custom models the Personal flavour added (Advanced, R62).
    var customCatalogURL: URL {
        root.appending(path: "custom-models.json")
    }

    /// Creates the root and marks it excluded from backup (spec 5.3).
    func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = root
        try root.setResourceValues(values)
    }

    /// Whether `model`'s repo, revision and file names are safe path components (a custom
    /// manifest comes from the Hub, so nothing in it may climb out of the store).
    static func isSafe(_ model: LocalModelManifest) -> Bool {
        let repoParts = model.repo.split(separator: "/", omittingEmptySubsequences: false)
        let revisionOK = model.revision.count == 40
            && model.revision.allSatisfy(\.isHexDigit)
        return repoParts.count == 2 && repoParts.allSatisfy(isSafeComponent) && revisionOK
            && model.files.allSatisfy { file in
                let parts = file.name.split(separator: "/", omittingEmptySubsequences: false)
                return !parts.isEmpty && parts.allSatisfy(isSafeComponent)
            }
    }

    private static func isSafeComponent(_ part: Substring) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return !part.isEmpty && part != "." && part != ".." && !part.hasPrefix(".")
            && part.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
    }
}
