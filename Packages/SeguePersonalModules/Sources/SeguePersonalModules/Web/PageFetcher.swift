import Foundation
import Plugins

/// Spec 8.2, 8.6 and 9 put together: one page per user action, paced per host, from the
/// in-memory cache when it was read in the last 10 minutes; a plain request first, and a
/// challenge page or a 403 goes **once** to the hidden WebKit loader. A site that blocks
/// plain requests outright (E-Chords) goes to WebKit directly. A cold WebKit store loads the
/// site's home page once first. A hard block on a chord site's last load path starts its
/// one-hour back-off; a challenge does not.
final class PageFetcher: Sendable {
    enum Route: Sendable, Hashable {
        case plainFirst
        case webKitOnly
    }

    private let plain: any PageLoader
    private let webKit: any PageLoader
    private let pacer: RequestPacer
    private let cache: PageCache<PageLoadRequest, LoadedPage>

    init(
        plain: any PageLoader,
        webKit: any PageLoader,
        pacer: RequestPacer,
        cache: PageCache<PageLoadRequest, LoadedPage> = PageCache(),
    ) {
        self.plain = plain
        self.webKit = webKit
        self.pacer = pacer
        self.cache = cache
    }

    func fetch(_ request: PageLoadRequest, route: Route) async throws(ImportFailure) -> LoadedPage {
        guard WebAddress.validated(request.url) != nil else { throw .notAPage }
        if let cached = cache.value(for: request) {
            return cached
        }
        let page: LoadedPage
        switch route {
        case .webKitOnly:
            page = try await loadThroughWebKit(request)
        case .plainFirst:
            do {
                page = try await paced(request, plain)
            } catch .challenged {
                page = try await loadThroughWebKit(request)
            } catch .blocked {
                page = try await loadThroughWebKit(request)
            } catch let .busy(retryAfter) {
                if request.backsOff {
                    await pacer.startBackOff(request.host)
                } else if let retryAfter {
                    await pacer.hold(request.host, for: retryAfter)
                }
                throw .busy(retryAfter: retryAfter)
            }
        }
        cache.store(page, for: request)
        return page
    }

    func clearCache() {
        cache.removeAll()
    }

    private func loadThroughWebKit(_ request: PageLoadRequest) async throws(ImportFailure)
        -> LoadedPage
    {
        var warmed = false
        if await webKit.needsWarmUp(for: request.url), let home = Self.homePage(of: request.url) {
            // One request to the host in the pacer; its outcome only primes the cookie store.
            _ = try? await paced(PageLoadRequest(url: home, marker: .document), webKit)
            warmed = true
        }
        do {
            var page = try await paced(request, webKit)
            page.warmUp = warmed
            return page
        } catch .blocked {
            if request.backsOff {
                await pacer.startBackOff(request.host)
            }
            throw .blocked
        }
    }

    private func paced(
        _ request: PageLoadRequest,
        _ loader: any PageLoader,
    ) async throws(ImportFailure) -> LoadedPage {
        try await pacer.perform(host: request.host) { () async throws(ImportFailure) in
            try await loader.load(request)
        }
    }

    static func homePage(of url: URL) -> URL? {
        guard let scheme = url.scheme,
              let host = url.host(percentEncoded: false) else { return nil }
        return URL(string: "\(scheme)://\(host)/")
    }
}
