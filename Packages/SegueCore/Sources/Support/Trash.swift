import Foundation

/// One item moved to the Trash: where it was and where it went.
public struct TrashedItem: Sendable, Equatable {
    public var original: URL
    public var trashed: URL

    public init(original: URL, trashed: URL) {
        self.original = original
        self.trashed = trashed
    }
}

/// What a delete moved to the Trash, in the order it was moved. Handing it back to the
/// store that made it restores the items (Edit > Undo). Empty when nothing was on disk.
public struct TrashReceipt: Sendable, Equatable {
    public var items: [TrashedItem]
    /// Items the delete had to leave in place (e.g. a song's sidecar whose move failed after
    /// its `.cho` was trashed). Reported to the user; never removed another way.
    public var leftBehind: [URL]

    public init(items: [TrashedItem] = [], leftBehind: [URL] = []) {
        self.items = items
        self.leftBehind = leftBehind
    }

    public var isEmpty: Bool {
        items.isEmpty
    }
}

/// Why an item could not be put back from the Trash.
public enum TrashRestoreError: Error, Equatable, LocalizedError {
    /// The trashed file is gone (the Trash was emptied, or it was put back by hand).
    case goneFromTrash(URL)
    /// Something else now sits at the item's original path.
    case originalTaken(URL)

    public var errorDescription: String? {
        switch self {
        case .goneFromTrash:
            "It is no longer in the Trash."
        case let .originalTaken(url):
            "Something else is now at “\(url.lastPathComponent)”."
        }
    }
}

public extension TrashReceipt {
    /// Moves every item back to its original path. Checks all items first, so a receipt
    /// whose files are partly gone or whose paths are partly taken changes nothing.
    func restore(using fileSystem: any FileSystem) throws {
        try restore(using: fileSystem) { $0.original }
    }

    /// Moves every item back to `destination(item)`, checking all items before moving any.
    func restore(
        using fileSystem: any FileSystem,
        to destination: (TrashedItem) -> URL,
    ) throws {
        for item in items {
            guard fileSystem.fileExists(at: item.trashed) else {
                throw TrashRestoreError.goneFromTrash(item.trashed)
            }
            let target = destination(item)
            guard !fileSystem.fileExists(at: target) else {
                throw TrashRestoreError.originalTaken(target)
            }
        }
        for item in items {
            try fileSystem.moveItem(from: item.trashed, to: destination(item))
        }
    }
}
