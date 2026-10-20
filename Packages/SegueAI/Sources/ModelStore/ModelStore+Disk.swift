import Foundation
import ModelPort

/// What is on disk: the installed check, partial bytes and folder clean-up.
extension ModelStore {
    /// Installed = the marker lists exactly the manifest's files and every file is there at
    /// its pinned size (the digests were checked when the marker was written).
    nonisolated func isInstalled(
        _ model: LocalModelManifest,
        in location: ModelStoreLocation,
    ) -> Bool {
        let folder = location.modelDirectory(for: model)
        guard let data = try? Data(contentsOf: folder.appending(
            path: ModelStoreLocation.installMarker,
        )),
            let marker = try? JSONDecoder().decode(InstallMarker.self, from: data),
            marker.files == model.files
        else { return false }
        return model.files.allSatisfy { file in
            FileDigest.fileSize(folder.appending(path: file.name)) == file.size
        }
    }

    nonisolated func partialBytes(
        _ model: LocalModelManifest,
        in location: ModelStoreLocation,
    ) -> Int64 {
        let folder = location.modelDirectory(for: model)
        let partial = location.partialDirectory(for: model)
        return model.files.reduce(0) { sum, file in
            if FileDigest.fileSize(folder.appending(path: file.name)) == file.size {
                return sum + file.size
            }
            return sum + min(
                FileDigest.fileSize(partial.appending(path: file.name)) ?? 0,
                file.size,
            )
        }
    }

    nonisolated func remainingBytes(
        _ model: LocalModelManifest,
        in location: ModelStoreLocation,
    ) -> Int64 {
        max(0, model.downloadBytes - partialBytes(model, in: location))
    }

    nonisolated func removeEmptyParents(of folder: URL, below root: URL) {
        var parent = folder.deletingLastPathComponent()
        let fileManager = FileManager.default
        while parent.standardizedFileURL.path.count > root.standardizedFileURL.path.count,
              (try? fileManager.contentsOfDirectory(atPath: parent.path))?.isEmpty == true
        {
            try? fileManager.removeItem(at: parent)
            parent = parent.deletingLastPathComponent()
        }
    }
}
