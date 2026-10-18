import ChordPro
import Foundation
import Support

// In-app import (WS2a 3.2, R15). Split in two so phase 3 can put its review sheet between
// "decoded" and "written" for files that need conversion (A29).

/// A file import left out, and why (shown in the summary's Details).
public struct ImportSkip: Sendable, Equatable {
    public var fileName: String
    public var reason: String

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}

/// A decoded file ready to become a song: `prepareImport` makes them, `commitImport` writes
/// them.
public struct ImportCandidate: Sendable, Equatable {
    /// Where it was read from (never modified).
    public var source: URL
    /// The text to write as the new `.cho` (UTF-8 on disk; a leading BOM is dropped).
    public var text: String
    /// The encoding it was converted from when it was not UTF-8 (e.g. "Windows Latin 1").
    public var convertedFrom: String?
    /// Metadata copied from a `<stem>.segue.json` next to the source (never its ID).
    public var metadata: Sidecar?

    public var fileName: String {
        source.lastPathComponent
    }

    /// The file name without its extension: the slug base when the song has no `{title}`.
    public var stem: String {
        source.deletingPathExtension().lastPathComponent
    }
}

/// What an import did.
public struct ImportSummary: Sendable, Equatable {
    public var imported: [SongRecord]
    public var skipped: [ImportSkip]
    /// One line per file that was converted to UTF-8: "<file>: converted from <encoding>".
    public var converted: [String]

    public init(imported: [SongRecord] = [], skipped: [ImportSkip] = [], converted: [String] = []) {
        self.imported = imported
        self.skipped = skipped
        self.converted = converted
    }
}

/// Limits and reasons of `prepareImport` (one place, so the UI and tests agree).
public enum SongImport {
    /// Files read per import; the rest are skipped.
    public static let maxFiles = 500
    /// Bigger files are not songs.
    public static let maxBytes = 1_048_576

    static let notAccepted = "Not a ChordPro or text file"
    static let limitReached = "Import limit of 500 files reached"
    static let tooLarge = "Too large to be a song"
    static let notText = "Not a text file"

    static func unreadable(_ error: any Error) -> String {
        "Could not be read: \(SongFiles.describe(error))"
    }

    static func duplicate(of title: String) -> String {
        "Already in your library as “\(title)”"
    }

    /// The UTF-8 byte order mark.
    static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
}

public extension LibraryStore {
    /// Imports the files and folders at `urls`: `prepareImport`, then `commitImport`.
    func importSongs(_ urls: [URL]) throws -> ImportSummary {
        let (candidates, skipped) = try prepareImport(urls)
        var summary = try commitImport(candidates)
        summary.skipped = skipped + summary.skipped
        return summary
    }

    /// Reads and decodes every importable file in `urls` (folders recursively; hidden files
    /// and packages skipped; at most `SongImport.maxFiles`). Nothing is written. Files that
    /// are not songs, or whose bytes are already in the library or earlier in this batch,
    /// come back as skips. Failures are per file.
    func prepareImport(_ urls: [URL]) throws -> ([ImportCandidate], [ImportSkip]) {
        let library = try openLibrary()
        var titlesByHash: [String: String] = [:]
        for song in library.songs.values {
            titlesByHash[song.contentHash] = song.sortTitle
        }
        var candidates: [ImportCandidate] = []
        var skipped: [ImportSkip] = []
        var seen = 0
        for url in expand(urls) {
            let name = url.lastPathComponent
            // A sidecar travels with its song (copied below); it is not a skipped file.
            if name.hasSuffix(LibraryRoot.sidecarSuffix) {
                continue
            }
            guard SongFileTypes.isImportable(url) else {
                skipped.append(ImportSkip(fileName: name, reason: SongImport.notAccepted))
                continue
            }
            seen += 1
            guard seen <= SongImport.maxFiles else {
                skipped.append(ImportSkip(fileName: name, reason: SongImport.limitReached))
                continue
            }
            switch decodeForImport(url) {
            case let .failure(skip):
                skipped.append(skip)
            case let .success(candidate):
                let bytes = Data(candidate.text.utf8)
                let hash = SongFiles.hash(bytes)
                if let title = titlesByHash[hash] {
                    skipped.append(ImportSkip(
                        fileName: name,
                        reason: SongImport.duplicate(of: title),
                    ))
                    continue
                }
                let (document, _) = ChordProParser.parse(candidate.text)
                let title = document.metadata.title.flatMap { $0.isEmpty ? nil : $0 }
                titlesByHash[hash] = title ?? Slug.make(from: candidate.stem)
                candidates.append(candidate)
            }
        }
        return (candidates, skipped)
    }

    /// Writes each candidate as a new song: `songs/<slug>.cho` (slug from `{title}`, else
    /// the source file name) and a fresh sidecar (new ID, carrying any copied metadata),
    /// then indexes it. A write failure skips that file and keeps what was already imported.
    func commitImport(_ candidates: [ImportCandidate]) throws -> ImportSummary {
        var summary = ImportSummary()
        for candidate in candidates {
            do {
                let metadata = candidate.metadata
                let record = try createSong(source: candidate.text, slugBase: candidate.stem) {
                    Self.copy(metadata, into: &$0)
                }
                summary.imported.append(record)
                if let encoding = candidate.convertedFrom {
                    summary.converted.append("\(candidate.fileName): converted from \(encoding)")
                }
            } catch {
                summary.skipped.append(ImportSkip(
                    fileName: candidate.fileName,
                    reason: "Could not be saved: \(SongFiles.describe(error))",
                ))
            }
        }
        return summary
    }
}

extension LibraryStore {
    /// Copies a neighbour sidecar's metadata (tags, proficiency, notes, cues, display and
    /// live prefs) into a new song's sidecar; its ID and dates stay the new song's (B-12).
    static func copy(_ metadata: Sidecar?, into sidecar: inout Sidecar) {
        guard let metadata else { return }
        sidecar.tags = metadata.tags
        sidecar.proficiency = metadata.proficiency
        sidecar.notes = metadata.notes
        sidecar.cues = metadata.cues
        sidecar.displayPrefs = metadata.displayPrefs
        sidecar.live = metadata.live
    }

    /// `urls` with folders expanded (recursively, sorted by path, hidden files and packages
    /// left out). Order is kept otherwise.
    private func expand(_ urls: [URL]) -> [URL] {
        var files: [URL] = []
        for url in urls {
            if fileSystem.directoryExists(at: url) {
                guard !Self.isPackage(url) else { continue }
                let children = (try? fileSystem.contentsOfDirectory(at: url)) ?? []
                files += expand(children)
            } else if !url.lastPathComponent.hasPrefix(".") {
                files.append(url)
            }
        }
        return files
    }

    /// Whether `url` is a package (an app, a bundle): imported as nothing, like Finder shows
    /// it as one item. A stat only; the bytes still go through `FileSystem`.
    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }

    /// Reads and decodes one file, or says why it is not a song.
    private func decodeForImport(_ url: URL) -> Result<ImportCandidate, ImportSkip> {
        let name = url.lastPathComponent
        let data: Data
        do {
            data = try fileSystem.readData(at: url)
        } catch {
            return .failure(ImportSkip(fileName: name, reason: SongImport.unreadable(error)))
        }
        guard data.count <= SongImport.maxBytes else {
            return .failure(ImportSkip(fileName: name, reason: SongImport.tooLarge))
        }
        guard !data.contains(0) else {
            return .failure(ImportSkip(fileName: name, reason: SongImport.notText))
        }
        let body = data.starts(with: SongImport.bom) ? data
            .dropFirst(SongImport.bom.count) : data[...]
        let (text, readOnly) = SongFiles.decodeText(Data(body))
        let convertedFrom: String? = if case let .notUTF8(encoding) = readOnly {
            encoding
        } else {
            nil
        }
        return .success(ImportCandidate(
            source: url,
            text: text,
            convertedFrom: convertedFrom,
            metadata: neighbourSidecar(of: url),
        ))
    }

    /// The editable `<stem>.segue.json` next to `url`, if there is one and it can be read.
    private func neighbourSidecar(of url: URL) -> Sidecar? {
        let neighbour = url.deletingPathExtension()
            .appendingPathExtension("segue.json")
        guard fileSystem.fileExists(at: neighbour),
              let data = try? fileSystem.readData(at: neighbour),
              case let .editable(sidecar, _) = SidecarCodec.decode(data, fallbackDate: .distantPast)
        else { return nil }
        return sidecar
    }
}

extension ImportSkip: Error {}
