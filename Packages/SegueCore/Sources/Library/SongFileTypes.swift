import Foundation

/// The one list of song file types (WS2a 3.2, I-10). Import and its open panel accept
/// `importExtensions`; the `.cho` document type, Open With and Quick Look claim only
/// `claimedExtensions` (`.pro` and `.txt` are too generic to claim, though `.pro` imports).
public enum SongFileTypes {
    /// Extensions File > Import Songs… and drag and drop accept (case-insensitive).
    /// `.crd` is not accepted in 0.5: it is mostly chords-over-lyrics, phase 3's converter.
    public static let importExtensions = ["cho", "chopro", "chordpro", "pro", "txt"]
    /// Extensions Segue registers as its document type.
    public static let claimedExtensions = ["cho", "chordpro", "chopro"]

    /// Whether `url`'s extension is one import accepts.
    public static func isImportable(_ url: URL) -> Bool {
        importExtensions.contains(url.pathExtension.lowercased())
    }
}
