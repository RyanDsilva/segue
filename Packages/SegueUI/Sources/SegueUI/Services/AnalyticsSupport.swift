import Foundation
import Library
import Services
import Support

public extension ServicesHub {
    /// The hub of view models that were not handed the app's: never sends anything.
    static let disabled = ServicesHub.inert()
}

extension SearchMatchTier {
    /// Row 17's tier for a search that had a query: the tier of the first result, `none`
    /// when nothing was found.
    init(_ tier: SearchTier?) {
        self = switch tier {
        case .exact: .exact
        case .spellingVariant: .spellingVariant
        case .looseVariant: .looseVariant
        case .fuzzy: .fuzzy
        case nil: .noResults
        }
    }
}

/// Records `Segue.Search.performed` once a search's results have stayed on screen for a
/// moment (WS3 spec 5 row 17: "after the as-you-type debounce settles"), so the partial
/// queries of someone still typing are never counted. The query itself is never recorded.
@MainActor
final class SearchRecorder {
    /// How long results must stay unchanged before the search counts.
    static let settle: Duration = .milliseconds(800)

    var services: ServicesHub = .disabled
    private var pending: Task<Void, Never>?

    /// Results for a non-blank query just landed in `context`.
    func resultsShown(_ context: SearchContext, tier: SearchTier?, count: Int) {
        pending?.cancel()
        let services = services
        let event = AnalyticsEvent.searchPerformed(
            context: context,
            matchTier: SearchMatchTier(count == 0 ? nil : tier),
            results: SmallBucket(count),
        )
        pending = Task {
            do {
                try await Task.sleep(for: Self.settle)
            } catch {
                return
            }
            services.record(event)
        }
    }

    /// The query changed or was cleared: the pending search does not count.
    func cancel() {
        pending?.cancel()
        pending = nil
    }
}

/// Days since the first launch, for the day buckets of rows 2 and 13. The date is kept in
/// the app's own defaults (never sent; only its bucket is).
enum FirstLaunch {
    static let defaultsKey = "analytics.firstLaunch"

    /// The bucket for today; the first call stores today as the first launch.
    static func days(defaults: UserDefaults, now: Date) -> DaysBucket {
        let first: Date
        if let stored = defaults.object(forKey: defaultsKey) as? Date {
            first = stored
        } else {
            defaults.set(now, forKey: defaultsKey)
            first = now
        }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: first),
            to: Calendar.current.startOfDay(for: now),
        ).day ?? 0
        return DaysBucket(days: days)
    }
}
