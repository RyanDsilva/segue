import Foundation
import Synchronization

/// Spec 9: an in-memory, per-launch cache, so Cancel then re-import, or a second look at a
/// preview, costs no request. At most `capacity` entries, each for `lifetime`; nothing is
/// ever written to disk. Cleared on memory pressure and when the library closes.
final class PageCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry {
        var value: Value
        var stored: Date
    }

    private let capacity: Int
    private let lifetime: TimeInterval?
    private let clock: any WebClock
    private let entries = Mutex<[(key: Key, entry: Entry)]>([])

    /// `lifetime` nil keeps entries for the launch (lyrics records by id).
    init(
        capacity: Int = 20,
        lifetime: Duration? = .seconds(600),
        clock: any WebClock = SystemWebClock(),
    ) {
        self.capacity = capacity
        self.lifetime = lifetime?.seconds
        self.clock = clock
    }

    func value(for key: Key) -> Value? {
        let now = clock.now()
        return entries.withLock { list in
            list.removeAll { item in
                lifetime.map { now.timeIntervalSince(item.entry.stored) > $0 } ?? false
            }
            return list.last { $0.key == key }?.entry.value
        }
    }

    func store(_ value: Value, for key: Key) {
        let entry = Entry(value: value, stored: clock.now())
        entries.withLock { list in
            list.removeAll { $0.key == key }
            list.append((key, entry))
            if list.count > capacity {
                list.removeFirst(list.count - capacity)
            }
        }
    }

    func removeAll() {
        entries.withLock { $0.removeAll() }
    }

    var count: Int {
        entries.withLock(\.count)
    }
}
