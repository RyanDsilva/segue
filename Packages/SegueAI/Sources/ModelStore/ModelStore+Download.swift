import Foundation
import ModelPort

/// The download job: every file in turn, then the install marker.
extension ModelStore {
    enum Event: Sendable {
        case verifying
        case progress(received: Int64, total: Int64)
        case transfer(FileTransfer?)
    }

    func handle(_ event: Event, for id: String) {
        guard jobs[id] != nil else { return }
        switch event {
        case .verifying:
            setTransient(id, .verifying)
        case let .progress(received, total):
            setTransient(id, .downloading(received: received, total: total))
        case let .transfer(transfer):
            jobs[id]?.transfer = transfer
            if jobs[id]?.task?.isCancelled == true {
                transfer?.cancel()
            }
        }
    }

    func finish(_ id: String, outcome: FileTransfer.Outcome) {
        jobs[id] = nil
        switch outcome {
        case .completed:
            transient[id] = nil
        case .cancelled:
            transient[id] = nil
        case let .failed(failure):
            transient[id] = .failed(failure)
        }
        publish()
    }

    /// Where a download goes and how it is fetched.
    struct Target {
        var model: LocalModelManifest
        var location: ModelStoreLocation
        var options: Options
    }

    /// Every file in turn: a file already in place is verified and kept, the rest are fetched
    /// into the partial folder, verified and moved in; the marker is written last.
    static func run(
        _ model: LocalModelManifest,
        location: ModelStoreLocation,
        options: Options,
        report: @escaping @Sendable (Event) async -> Void,
    ) async -> FileTransfer.Outcome {
        let folder = location.modelDirectory(for: model)
        let total = model.downloadBytes
        var done: Int64 = 0
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .failed(FileTransfer.failure(for: error))
        }
        for file in model.files {
            if Task.isCancelled {
                return .cancelled
            }
            let target = Target(model: model, location: location, options: options)
            let outcome = await place(file, into: target, done: done, report: report)
            guard outcome == .completed else { return outcome }
            done += file.size
            await report(.progress(received: done, total: total))
        }
        do {
            let marker = InstallMarker(
                id: model.id,
                repo: model.repo,
                revision: model.revision,
                files: model.files,
            )
            try JSONEncoder().encode(marker).write(
                to: folder.appending(path: ModelStoreLocation.installMarker),
                options: .atomic,
            )
        } catch {
            return .failed(FileTransfer.failure(for: error))
        }
        try? FileManager.default.removeItem(at: location.partialDirectory(for: model))
        return .completed
    }

    /// One file into the model folder: kept when the copy there verifies, else downloaded
    /// (resuming its partial file), verified and moved in.
    private static func place(
        _ file: LocalModelManifest.File,
        into destination: Target,
        done: Int64,
        report: @escaping @Sendable (Event) async -> Void,
    ) async -> FileTransfer.Outcome {
        let (model, location, options) = (
            destination.model,
            destination.location,
            destination.options,
        )
        let fileManager = FileManager.default
        let target = location.modelDirectory(for: model).appending(path: file.name)
        let partial = location.partialDirectory(for: model).appending(path: file.name)
        if fileManager.fileExists(atPath: target.path) {
            await report(.verifying)
            if FileDigest.verify(target, against: file) {
                return .completed
            }
            try? fileManager.removeItem(at: target)
        }
        let total = model.downloadBytes
        let throttle = ProgressThrottle()
        guard let transfer = FileTransfer(
            url: options.baseURL.appending(path: model.repo)
                .appending(path: "resolve").appending(path: model.revision)
                .appending(path: file.name),
            partial: partial,
            file: file,
            appVersion: options.appVersion,
            progress: { bytes in
                guard throttle.shouldReport() else { return }
                Task { await report(.progress(received: done + bytes, total: total)) }
            },
        ) else { return .failed(.other) }
        await report(.transfer(transfer))
        let outcome = await transfer.run()
        await report(.transfer(nil))
        guard outcome == .completed else { return outcome }
        do {
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: partial, to: target)
        } catch {
            return .failed(FileTransfer.failure(for: error))
        }
        return .completed
    }
}

/// Written into a model's folder once every file is verified.
struct InstallMarker: Codable, Equatable {
    var id: String
    var repo: String
    var revision: String
    var files: [LocalModelManifest.File]
}

/// At most five progress reports a second.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now - .seconds(1)

    func shouldReport() -> Bool {
        lock.withLock {
            let now = ContinuousClock.now
            guard now - last >= .milliseconds(200) else { return false }
            last = now
            return true
        }
    }
}
