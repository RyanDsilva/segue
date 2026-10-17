import ChordPro
import Foundation
import Support
import Synchronization

/// One `songs/*.cho` as seen by a scan, before orphan sidecars are created.
enum ScanResult: Sendable {
    /// Loaded (or unchanged since `previous`, and reused as is).
    case loaded(LoadedSong)
    /// No sidecar on disk: `song` carries a placeholder sidecar until `adoptOrphan` writes
    /// one. Orphans are adopted one at a time, in path order, so IDs are handed out
    /// deterministically.
    case orphan(LoadedSong)
    /// The file could not be read; the rest of the library still loads.
    case failed(slug: String, message: String)
}

/// What a scan learns about one song from `stat` alone.
private struct ScanProbe: Sendable {
    var slug: String
    /// The song as loaded at this path before, if it was.
    var previous: LoadedSong?
    var choAttributes: FileAttributes
    /// Nil when the sidecar is not on disk (an orphan).
    var sidecarStamp: FileStamp?

    /// The text is reused from `previous` unless the `.cho`'s mtime or size moved.
    var readsSource: Bool {
        previous?.choStamp != FileStamp(choAttributes)
    }

    /// Likewise for the sidecar.
    var readsSidecar: Bool {
        sidecarStamp != nil && previous?.sidecarStamp != sidecarStamp
    }
}

extension SongFiles {
    /// Loads every `songs/<slug>.cho` with its sidecar, one result per slug, in order.
    /// `previous` (keyed by relative path) is what the last scan loaded: a file whose
    /// modification time and size are unchanged is not read again. Changed files are read
    /// under one coordinated read of `songs/`, then hashed and parsed concurrently.
    func scan(_ slugs: [String], previous: [String: LoadedSong]) -> [ScanResult] {
        // Stat before reading: a write racing the read leaves a stamp older than the bytes,
        // so the next scan reads the file again instead of trusting stale content.
        let probes = Self.concurrentMap(slugs) { slug in
            Result { try probe(slug, previous: previous[Self.relativePath(slug: slug)]) }
        }
        var urls: [URL] = []
        var sourceSlots = [Int?](repeating: nil, count: slugs.count)
        var sidecarSlots = [Int?](repeating: nil, count: slugs.count)
        for (index, probe) in probes.enumerated() {
            guard case let .success(probe) = probe else { continue }
            if probe.readsSource {
                sourceSlots[index] = urls.count
                urls.append(choURL(slug: probe.slug))
            }
            if probe.readsSidecar {
                sidecarSlots[index] = urls.count
                urls.append(sidecarURL(slug: probe.slug))
            }
        }
        let contents = urls.isEmpty ? [] : fileSystem.readFiles(urls, in: root.songsDirectory)
        let (sources, sidecars) = (sourceSlots, sidecarSlots)

        return Self.concurrentMap(Array(slugs.indices)) { index in
            do {
                return try load(
                    probes[index].get(),
                    source: sources[index].map { contents[$0] },
                    sidecar: sidecars[index].map { contents[$0] },
                )
            } catch {
                return .failed(slug: slugs[index], message: Self.describe(error))
            }
        }
    }

    /// Gives an orphan `.cho` its sidecar: a new ID (or the ID `previous` already had in this
    /// session). If the sidecar can't be written the song still loads, with an ID derived
    /// from its path (stable while writing keeps failing), and the failure is returned.
    func adoptOrphan(_ orphan: LoadedSong, previous: LoadedSong?) -> (LoadedSong, String?) {
        var song = orphan
        let url = sidecarURL(slug: song.slug)
        let now = SegueJSON.stamp(clock.now())
        let id = previous?.record.id ?? SongID(ids.next())
        let sidecar = Sidecar(id: id, createdAt: now, updatedAt: now)
        do {
            let data = try SidecarCodec.encode(sidecar)
            try fileSystem.writeAtomically(data, to: url)
            song.sidecarData = data
            song.sidecarStamp = try FileStamp(fileSystem.attributes(at: url))
            song.record.sidecar = sidecar
            song.record.id = id
            song.record.hasDerivedID = false
            return (song, nil)
        } catch {
            let derived = previous?.record.id ?? Self.derivedID(slug: song.slug)
            song.record.sidecar = Sidecar(id: derived, createdAt: now, updatedAt: now)
            song.record.id = derived
            song.record.hasDerivedID = previous.map(\.record.hasDerivedID) ?? true
            song.sidecarData = nil
            return (song, "Its metadata file could not be created: \(Self.describe(error))")
        }
    }

    /// When several files carry the same ID (e.g. a Finder-duplicated song + sidecar), the
    /// original keeps it: the file that held it before this scan (`previousPaths`), else the
    /// oldest sidecar `createdAt`, else the oldest `.cho` creation date, else the shortest
    /// slug ("song" beats "song copy"), else the first by path. The others get new IDs,
    /// persisted in their sidecar when it is writable; failures land in `issues`.
    func resolveDuplicateIDs(
        _ songs: [LoadedSong],
        previousPaths: [SongID: String],
        issues: inout [LibraryLoadIssue],
    ) -> [LoadedSong] {
        let groups = Dictionary(grouping: songs.indices, by: { songs[$0].record.id })
        var result = songs
        // Sorted so new IDs are handed out in a deterministic order.
        for (id, indices) in groups.sorted(by: { $0.key < $1.key }) where indices.count > 1 {
            let ordered = indices.sorted { lhs, rhs in
                Self.isMoreOriginal(songs[lhs], than: songs[rhs], previousPath: previousPaths[id])
            }
            for index in ordered.dropFirst() {
                do {
                    result[index] = try reassignID(songs[index])
                } catch {
                    var song = songs[index]
                    song.record.id = Self.derivedID(slug: song.slug)
                    song.record.sidecar.id = song.record.id
                    song.record.hasDerivedID = true
                    result[index] = song
                    issues.append(LibraryLoadIssue(
                        relativePath: Self.sidecarRelativePath(slug: song.slug),
                        message: "Duplicate song ID; a new one could not be saved: "
                            + Self.describe(error),
                    ))
                }
            }
        }
        return result
    }

    // MARK: Private

    private static func isMoreOriginal(
        _ lhs: LoadedSong,
        than rhs: LoadedSong,
        previousPath: String?,
    ) -> Bool {
        let lhsHeld = lhs.record.relativePath == previousPath
        let rhsHeld = rhs.record.relativePath == previousPath
        if lhsHeld != rhsHeld {
            return lhsHeld
        }
        if lhs.record.sidecar.createdAt != rhs.record.sidecar.createdAt {
            return lhs.record.sidecar.createdAt < rhs.record.sidecar.createdAt
        }
        let lhsCreated = lhs.choCreated ?? .distantFuture
        let rhsCreated = rhs.choCreated ?? .distantFuture
        if lhsCreated != rhsCreated {
            return lhsCreated < rhsCreated
        }
        if lhs.slug.count != rhs.slug.count {
            return lhs.slug.count < rhs.slug.count
        }
        return lhs.record.relativePath < rhs.record.relativePath
    }

    private func probe(_ slug: String, previous: LoadedSong?) throws -> ScanProbe {
        let sidecarURL = sidecarURL(slug: slug)
        return try ScanProbe(
            slug: slug,
            previous: previous,
            choAttributes: fileSystem.attributes(at: choURL(slug: slug)),
            sidecarStamp: fileSystem.fileExists(at: sidecarURL)
                ? FileStamp(fileSystem.attributes(at: sidecarURL))
                : nil,
        )
    }

    /// Builds the song from `probe` and the bytes read for it (nil: unchanged, reuse
    /// `probe.previous`).
    private func load(
        _ probe: ScanProbe,
        source: Result<Data, any Error>?,
        sidecar: Result<Data, any Error>?,
    ) throws -> ScanResult {
        var (record, textReadOnly) = try loadText(probe, source: source)
        let sidecarData = try loadSidecar(probe, data: sidecar, into: &record)
        let song = LoadedSong(
            record: record,
            slug: probe.slug,
            choStamp: FileStamp(probe.choAttributes),
            choCreated: probe.choAttributes.creationDate,
            sidecarStamp: probe.sidecarStamp,
            sidecarData: sidecarData.data,
            sidecarReadOnly: sidecarData.readOnly,
            textReadOnly: textReadOnly,
        )
        return probe.sidecarStamp == nil ? .orphan(song) : .loaded(song)
    }

    /// The record for the `.cho` text: `previous`'s when the bytes are unchanged (not read,
    /// or read and hashing the same), else freshly decoded and parsed. Its ID and sidecar are
    /// placeholders until `loadSidecar`.
    private func loadText(
        _ probe: ScanProbe,
        source: Result<Data, any Error>?,
    ) throws -> (SongRecord, ReadOnlyReason?) {
        let slug = probe.slug
        let previous = probe.previous
        var record: SongRecord
        let textReadOnly: ReadOnlyReason?
        if let previous, source == nil {
            (record, textReadOnly) = (previous.record, previous.textReadOnly)
        } else {
            let data = try source?.get() ?? fileSystem.readData(at: choURL(slug: slug))
            let hash = Self.hash(data)
            if let previous, previous.contentHash == hash {
                (record, textReadOnly) = (previous.record, previous.textReadOnly)
            } else {
                let text: String
                (text, textReadOnly) = Self.decodeText(data)
                let (document, diagnostics) = ChordProParser.parse(text)
                let placeholderID = previous?.record.id ?? Self.derivedID(slug: slug)
                record = SongRecord(
                    id: placeholderID,
                    relativePath: Self.relativePath(slug: slug),
                    source: text,
                    document: document,
                    diagnostics: diagnostics,
                    sidecar: Sidecar(
                        id: placeholderID,
                        createdAt: .distantPast,
                        updatedAt: .distantPast,
                    ),
                )
            }
            record.revision.contentHash = hash
        }
        record.relativePath = Self.relativePath(slug: slug)
        return (record, textReadOnly)
    }

    /// Fills `record`'s ID, sidecar and revision from the sidecar bytes (nil: unchanged since
    /// `previous`, or not on disk). Returns the bytes and why the sidecar blocks edits.
    private func loadSidecar(
        _ probe: ScanProbe,
        data: Result<Data, any Error>?,
        into record: inout SongRecord,
    ) throws -> (data: Data?, readOnly: ReadOnlyReason?) {
        let previous = probe.previous
        var sidecarData: Data?
        var readOnly: ReadOnlyReason?
        if let data = try data?.get() {
            sidecarData = data
            if let previous, previous.sidecarData == data {
                (record.sidecar, record.id) = (previous.record.sidecar, previous.record.id)
                record.hasDerivedID = previous.record.hasDerivedID
                readOnly = previous.sidecarReadOnly
            } else {
                let decoded = decodeSidecar(data, slug: probe.slug, previous: previous)
                (record.sidecar, record.id) = (decoded.sidecar, decoded.sidecar.id)
                record.hasDerivedID = decoded.derivedID
                readOnly = decoded.readOnly
            }
        } else if probe.sidecarStamp != nil, let previous {
            // Unchanged since `previous`.
            sidecarData = previous.sidecarData
            (record.sidecar, record.id) = (previous.record.sidecar, previous.record.id)
            record.hasDerivedID = previous.record.hasDerivedID
            readOnly = previous.sidecarReadOnly
        }
        record.revision.sidecarHash = sidecarData.map(Self.hash)
        return (sidecarData, readOnly)
    }

    /// `elements.map(transform)`, run on all cores.
    private static func concurrentMap<Element: Sendable, Mapped: Sendable>(
        _ elements: [Element],
        _ transform: @Sendable (Element) -> Mapped,
    ) -> [Mapped] {
        let results = Mutex([Mapped?](repeating: nil, count: elements.count))
        DispatchQueue.concurrentPerform(iterations: elements.count) { index in
            let mapped = transform(elements[index])
            results.withLock { $0[index] = mapped }
        }
        return results.withLock { $0.compactMap(\.self) }
    }
}
