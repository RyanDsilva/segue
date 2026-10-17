import Foundation
import Library

/// Phase 2 (unit D): library metadata editing (tags, proficiency, notes, cues).
public extension LibraryViewModel {
    /// Saves song `id`'s tags, proficiency, notes and cues to its sidecar, then reloads so
    /// lists, chips and search see the change. Failures are shown in the error banner.
    @discardableResult
    func updateMetadata(id: SongID, _ metadata: SongMetadata) async -> SongRecord? {
        do {
            let record = try await store.updateMetadata(id: id, metadata)
            await reload()
            return record
        } catch {
            errorMessage = UserMessage.describe(error)
            await reload()
            return nil
        }
    }

    /// Changes one part of song `id`'s metadata, starting from what the catalog holds.
    func editMetadata(id: SongID, _ change: (inout SongMetadata) -> Void) async {
        guard let record = song(id: id) else { return }
        var metadata = SongMetadata(record.sidecar)
        change(&metadata)
        guard metadata != SongMetadata(record.sidecar) else { return }
        await updateMetadata(id: id, metadata)
    }

    /// Known tags, most used first (for chips and token parsing).
    var tagNames: [String] {
        tags.map(\.tag)
    }
}
