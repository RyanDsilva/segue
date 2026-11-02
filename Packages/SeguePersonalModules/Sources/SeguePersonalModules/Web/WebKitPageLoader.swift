import Foundation
import Plugins
import WebKit

/// The hidden WebKit loader (spec 8.6, R179, R182, R183, R184). One on-demand `WKWebView`,
/// in no window, used for one page at a time behind the `RequestPacer` and torn down 30 s
/// after its last use so its WebContent process exits. A dedicated persistent cookie store
/// keeps a clearance between loads and launches; its disk and memory caches are cleared
/// after each load, so no page or lyric stays on disk. WebKit's own user agent for the whole
/// session, JavaScript on, media and pop-ups off, downloads refused, ads and trackers
/// blocked. The main frame stays within the import's address rules; subframes (the
/// challenge's own) load. Never clicks, solves or injects into a challenge: an interactive
/// check ends the load at once as `.challenged`, any other waits up to 12 s.
@MainActor
final class WebKitPageLoader: NSObject, PageLoader, ChallengeViewSource, WKNavigationDelegate,
    WKUIDelegate
{
    /// The store's fixed identity, owned by this package (never `.default()`, never
    /// `.nonPersistent()`). Clear Site Data removes it with `removeDataStoreForIdentifier`.
    static let storeIdentifier = UUID(uuid: (
        0x5E, 0x6E, 0x0A, 0x11, 0x9C, 0x4D, 0x4F, 0x7B, 0x8B, 0x2A, 0x71, 0xD3, 0xC0, 0xF4, 0xE9,
        0xA1,
    ))
    static let idleTeardown: Duration = .seconds(30)
    static let navigationTimeout: Duration = .seconds(20)
    static let markerTimeout: Duration = .seconds(8)

    private var view: WKWebView?
    private var page: URL?
    private var mainResponse: HTTPURLResponse?
    private var navigation: CheckedContinuation<Bool, Never>?
    private var teardown: Task<Void, Never>?
    private var ruleList: WKContentRuleList?
    /// Open Here shows the view: it is not torn down meanwhile.
    private var isPresented = false

    override nonisolated init() {
        super.init()
    }

    // MARK: PageLoader

    nonisolated func load(_ request: PageLoadRequest) async throws(ImportFailure) -> LoadedPage {
        let result = await loadOnMain(request)
        return try result.get()
    }

    nonisolated func needsWarmUp(for url: URL) async -> Bool {
        await hasNoCookies(for: url)
    }

    /// Removes the whole store (Settings > Clear Site Data).
    static func clearSiteData() async {
        try? await WKWebsiteDataStore.remove(forIdentifier: storeIdentifier)
    }

    // MARK: Loading

    private func loadOnMain(_ request: PageLoadRequest) async -> Result<LoadedPage, ImportFailure> {
        teardown?.cancel()
        defer { scheduleTeardown() }
        let view = await prepareView()
        defer { Task { await self.clearCaches() } }
        guard await navigate(view, to: request.url) else {
            return .failure(Task.isCancelled ? .cancelled : .timedOut)
        }
        let challenge: ChallengeKind
        switch await awaitClearance(in: view) {
        case let .failure(failure): return .failure(failure)
        case let .success(kind): challenge = kind
        }
        await waitForMarker(request.marker, in: view)
        guard let text = await read(request, in: view) else {
            return .failure(.noChart(.notFound))
        }
        return .success(LoadedPage(
            url: view.url ?? request.url, text: text, loadPath: .webKit, challenge: challenge,
        ))
    }

    /// Loads `url` as the main frame; false when it timed out or the task was cancelled.
    private func navigate(_ view: WKWebView, to url: URL) async -> Bool {
        page = url
        mainResponse = nil
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.navigationTimeout)
            if !Task.isCancelled {
                self?.finishNavigation(false)
            }
        }
        defer { timeout.cancel() }
        let finished = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                navigation = continuation
                view.load(URLRequest(url: url, timeoutInterval: 20))
            }
        } onCancel: {
            Task { @MainActor in self.finishNavigation(false) }
        }
        return finished && !Task.isCancelled
    }

    /// Waits for a challenge to clear on its own (never for an interactive one); the result
    /// is the challenge type first seen (`.notChallenged` when there was none).
    private func awaitClearance(in view: WKWebView) async -> Result<ChallengeKind, ImportFailure> {
        var signals = await signals(in: view)
        guard case let .challenge(kind) = ChallengeDetector.verdict(signals) else {
            return ChallengeDetector.verdict(signals) == .blocked ? .failure(.blocked)
                : .success(.notChallenged)
        }
        let deadline = ContinuousClock.now + ChallengeDetector.wait(for: kind)
        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return .failure(.cancelled)
            }
            signals = await self.signals(in: view)
            switch ChallengeDetector.verdict(signals) {
            case .challenge: continue
            case .blocked: return .failure(.blocked)
            case .page: return .success(kind)
            }
        }
        return .failure(.challenged)
    }

    private func prepareView() async -> WKWebView {
        if let view {
            return view
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeIdentifier)
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        if ruleList == nil {
            ruleList = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: ImportContentRules.identifier,
                encodedContentRuleList: ImportContentRules.json,
            )
        }
        if let ruleList {
            configuration.userContentController.add(ruleList)
        }
        let view = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1100, height: 800),
            configuration: configuration,
        )
        view.navigationDelegate = self
        view.uiDelegate = self
        self.view = view
        return view
    }

    private func scheduleTeardown() {
        guard !isPresented else { return }
        teardown = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTeardown)
            guard !Task.isCancelled else { return }
            self?.view?.stopLoading()
            self?.view = nil
        }
    }

    private func clearCaches() async {
        await WKWebsiteDataStore(forIdentifier: Self.storeIdentifier).removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast,
        )
    }

    private func hasNoCookies(for url: URL) async -> Bool {
        let site = NavigationRule.registrableDomain(WebAddress.siteHost(url))
        let cookies = await WKWebsiteDataStore(forIdentifier: Self.storeIdentifier)
            .httpCookieStore.allCookies()
        return !cookies.contains { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie
                .domain
            return WebAddress.host(domain, isWithin: site)
        }
    }

    private func finishNavigation(_ finished: Bool) {
        navigation?.resume(returning: finished)
        navigation = nil
    }

    // MARK: Reading the page

    /// One script gathers the challenge facts (spec 8.6); `ChallengeDetector` decides.
    private static let signalScript = """
    const html = document.documentElement ? document.documentElement.outerHTML : '';
    const m = html.match(/cType:\\s*'([A-Za-z-]+)'/);
    return {
      title: document.title || '',
      element: !!document.querySelector('#challenge-form, #challenge-running, #challenge-stage, \
    .cf-turnstile, iframe[src*="challenges.cloudflare.com"], input[name="cf-turnstile-response"]'),
      blockText: html.includes('Sorry, you have been blocked'),
      cType: m ? m[1] : null,
    };
    """

    private func signals(in view: WKWebView) async -> PageSignals {
        let value = try? await view.callAsyncJavaScript(
            Self.signalScript, contentWorld: .world(name: "SegueImport"),
        ) as? [String: Any]
        return PageSignals(
            status: mainResponse?.statusCode ?? 200,
            mitigated: mainResponse?.value(forHTTPHeaderField: "cf-mitigated"),
            title: value?["title"] as? String ?? "",
            hasChallengeElement: value?["element"] as? Bool ?? false,
            hasBlockText: value?["blockText"] as? Bool ?? false,
            cType: value?["cType"] as? String,
        )
    }

    private static let storeScript = """
    return (window.UGAPP && window.UGAPP.store)
      ? JSON.stringify({store: window.UGAPP.store}) : null;
    """

    private static let fetchScript = """
    const r = await fetch(target, {credentials: 'include'});
    return r.ok ? await r.text() : null;
    """

    private static func markerScript(_ marker: ReadyMarker) -> String {
        switch marker {
        case .tabStore:
            "return !!(window.UGAPP && window.UGAPP.store) || !!document.querySelector('.js-store')"
        case .chordPre:
            "return !!document.querySelector('pre');"
        case .document:
            "return document.readyState === 'complete';"
        }
    }

    private func waitForMarker(_ marker: ReadyMarker, in view: WKWebView) async {
        let deadline = ContinuousClock.now + Self.markerTimeout
        while ContinuousClock.now < deadline {
            let ready = try? await view.callAsyncJavaScript(
                Self.markerScript(marker), contentWorld: .world(name: "SegueImport"),
            ) as? Bool
            if ready == true {
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        if marker == .document {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// JSON first (spec 8.6): UG's store wrapped as `{store: ...}` so one parser fits both
    /// shapes, or an in-page `fetch` riding on the page's own cookies; then the server HTML
    /// from `fetch(location.href)`; then `outerHTML`.
    private func read(_ request: PageLoadRequest, in view: WKWebView) async -> String? {
        let world = WKContentWorld.world(name: "SegueImport")
        if request.marker == .tabStore, request.inPageFetch == nil,
           let store = try? await view.callAsyncJavaScript(
               Self.storeScript,
               contentWorld: .page,
           ) as? String
        {
            return store
        }
        let target = request.inPageFetch ?? view.url?.absoluteString ?? request.url.absoluteString
        if let text = try? await view.callAsyncJavaScript(
            Self.fetchScript,
            arguments: ["target": target],
            contentWorld: world,
        ) as? String {
            return text
        }
        guard request.inPageFetch == nil else { return nil }
        return try? await view.evaluateJavaScript("document.documentElement.outerHTML") as? String
    }

    // MARK: Open Here (spec 8.6, R183)

    /// The hidden view, shown as it is (same store, same user agent, no reload). When it was
    /// torn down or shows another site, it loads `url` first so the owner sees the check.
    func presentChallenge(for url: URL) async -> WKWebView {
        teardown?.cancel()
        isPresented = true
        let view = await prepareView()
        let site = NavigationRule.registrableDomain(WebAddress.siteHost(url))
        let shown = view.url.map { NavigationRule.registrableDomain(WebAddress.siteHost($0)) }
        if shown != site {
            page = url
            mainResponse = nil
            view.load(URLRequest(url: url, timeoutInterval: 20))
        }
        return view
    }

    /// Polls the shown page until its check has cleared; false when the task was cancelled
    /// or the view went away. The app never clicks or injects into the check.
    func waitUntilCleared() async -> Bool {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return false
            }
            guard let view else { return false }
            if await ChallengeDetector.verdict(signals(in: view)) == .page {
                return true
            }
        }
        return false
    }

    /// The sheet closed: the view leaves it and is torn down after its idle time.
    func endPresentation() {
        isPresented = false
        view?.removeFromSuperview()
        scheduleTeardown()
    }

    // MARK: WKNavigationDelegate

    func webView(
        _: WKWebView,
        decidePolicyFor action: WKNavigationAction,
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let page else { return .cancel }
        let isMain = action.targetFrame?.isMainFrame ?? true
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" {
            return isMain && url.absoluteString != "about:blank" ? .cancel : .allow
        }
        return NavigationRule.allows(url, isMainFrame: isMain, page: page) ? .allow : .cancel
    }

    func webView(
        _: WKWebView,
        decidePolicyFor response: WKNavigationResponse,
    ) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame {
            mainResponse = response.response as? HTTPURLResponse
        }
        return response.canShowMIMEType ? .allow : .cancel
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        finishNavigation(true)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
        finishNavigation(true)
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: any Error,
    ) {
        // A challenge often replaces the first navigation (code 102, frame load interrupted).
        finishNavigation((error as NSError).code == 102)
    }

    // MARK: WKUIDelegate

    /// Pop-ups are refused.
    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures,
    ) -> WKWebView? {
        nil
    }
}
