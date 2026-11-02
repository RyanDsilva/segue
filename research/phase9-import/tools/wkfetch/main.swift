// wkfetch: the hidden WebKit loader of P9-4 spec 8.6 as a research tool (step a3). Loads each
// URL in one WKWebView on a dedicated persistent WKWebsiteDataStore(forIdentifier:), WebKit's
// own user agent, optional ad and tracker rule list, then reads the server HTML from inside
// the page (fetch(location.href) in a separate content world) with outerHTML as fallback.
// Never clicks, solves or injects into a challenge: a page still challenged after the wait
// is reported and skipped.
//
// Usage: wkfetch [--store UUID] [--mode hidden|behind|visible] [--rules FILE] [--warmup URL]
//                [--wait 12] [--gap 5] [--outdir DIR] [--api PATH] URL...
// --api: after the page loads, fetch PATH (same origin, the page's cookies) from inside the
// page and save that response instead of the page (E-Chords' /api/search, spec 6.11).
import AppKit
import WebKit

struct Options {
    var store = UUID(uuidString: "6F1A0B7E-1C2D-4E5F-8A9B-0C1D2E3F4A5B")!
    var mode = "hidden"
    var rules: String?
    var warmup: URL?
    var wait = 12.0
    var gap = 5.0
    var outdir: String?
    var api: String?
    var urls: [URL] = []
}

func parse() -> Options {
    var options = Options()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = args.next() {
        switch arg {
        case "--store": options.store = UUID(uuidString: args.next() ?? "") ?? UUID()
        case "--mode": options.mode = args.next() ?? "hidden"
        case "--rules": options.rules = args.next()
        case "--warmup": options.warmup = URL(string: args.next() ?? "")
        case "--wait": options.wait = Double(args.next() ?? "") ?? 12
        case "--gap": options.gap = Double(args.next() ?? "") ?? 5
        case "--outdir": options.outdir = args.next()
        case "--api": options.api = args.next()
        default: if let url = URL(string: arg) { options.urls.append(url) }
        }
    }
    return options
}

let challengeProbe = """
const t = document.title || '';
const html = document.documentElement ? document.documentElement.outerHTML : '';
const m = html.match(/cType:\\s*'([a-z-]+)'/);
return {
  challenged: /Just a moment|Attention Required|Verifying/.test(t)
    || !!document.querySelector('#challenge-form, #challenge-running, #challenge-stage, .cf-turnstile, iframe[src*="challenges.cloudflare.com"], input[name="cf-turnstile-response"]'),
  blockedText: /Sorry, you have been blocked/.test(html),
  cType: m ? m[1] : null,
  title: t,
};
"""

@MainActor
final class Loader: NSObject, WKNavigationDelegate {
    let options: Options
    var view: WKWebView!
    var window: NSWindow?
    var finished: CheckedContinuation<Void, Never>?
    var mainStatus: [Int] = []
    var mitigated = false

    init(options: Options) { self.options = options }

    func setUp() async {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = WKWebsiteDataStore(forIdentifier: options.store)
        conf.preferences.inactiveSchedulingPolicy = .none
        conf.mediaTypesRequiringUserActionForPlayback = .all
        if let path = options.rules, let json = try? String(contentsOfFile: path, encoding: .utf8) {
            do {
                let list = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "wkfetch-import-rules", encodedContentRuleList: json)
                if let list { conf.userContentController.add(list) }
            } catch { print("rules: \(error)") }
        }
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 800), configuration: conf)
        view.navigationDelegate = self
        if options.mode != "hidden" {
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1100, height: 800),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            if options.mode == "visible" {
                NSApp.setActivationPolicy(.regular)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            } else {
                window.orderBack(nil)
            }
            self.window = window
        }
    }

    func load(_ url: URL) async -> (ok: Bool, summary: String, html: String?) {
        mainStatus = []
        mitigated = false
        let start = Date()
        await withCheckedContinuation { continuation in
            finished = continuation
            view.load(URLRequest(url: url))
        }
        var probe = await challenge()
        let firstReady = Date().timeIntervalSince(start)
        if (probe["challenged"] as? Bool) == true || mitigated {
            let cType = probe["cType"] as? String
            if cType != "interactive" {
                let deadline = Date().addingTimeInterval(options.wait)
                while Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(500))
                    probe = await challenge()
                    if (probe["challenged"] as? Bool) != true { break }
                }
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        let still = (probe["challenged"] as? Bool) == true
        let blocked = (probe["blockedText"] as? Bool) == true
        var summary = String(format: "status %@ mitigated %@ cType %@ ready %.2fs total %.2fs",
                             mainStatus.map(String.init).joined(separator: ","), String(mitigated),
                             (probe["cType"] as? String) ?? "-", firstReady, elapsed)
        if still { return (false, "CHALLENGED " + summary, nil) }
        if blocked { return (false, "BLOCKED " + summary, nil) }
        var html: String?
        do {
            let value = try await view.callAsyncJavaScript(
                "const r = await fetch(target, {credentials: 'include'}); return r.ok ? await r.text() : null;",
                arguments: ["target": options.api ?? url.absoluteString],
                contentWorld: .defaultClient)
            html = value as? String
        } catch { summary += " fetch-failed" }
        if html == nil {
            html = try? await view.evaluateJavaScript("document.documentElement.outerHTML") as? String
            summary += " outerHTML"
        }
        return (true, "OK " + summary, html)
    }

    func challenge() async -> [String: Any] {
        (try? await view.callAsyncJavaScript(challengeProbe, contentWorld: .defaultClient) as? [String: Any]) ?? [:]
    }

    func webView(_: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
            mainStatus.append(http.statusCode)
            if http.value(forHTTPHeaderField: "cf-mitigated") == "challenge" { mitigated = true }
        }
        return .allow
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) { resume() }
    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: any Error) { resume() }
    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: any Error) { resume() }

    private func resume() {
        finished?.resume()
        finished = nil
    }

    /// Spec 8.6: caches cleared after each load, cookies and site storage kept.
    func clearCaches() async {
        await view.configuration.websiteDataStore.removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache], modifiedSince: .distantPast)
    }
}

func slug(_ url: URL) -> String {
    let raw = (url.host() ?? "") + url.path() + (url.query().map { "_" + $0 } ?? "")
    return String(raw.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }.prefix(150))
}

let options = parse()
NSApplication.shared.setActivationPolicy(.prohibited)
Task { @MainActor in
    let loader = Loader(options: options)
    await loader.setUp()
    let cookies = await options.store.uuidString.isEmpty ? [] :
        loader.view.configuration.websiteDataStore.httpCookieStore.allCookies()
    print("store \(options.store) cookies \(cookies.count) mode \(options.mode) rules \(options.rules != nil)")
    if let warm = options.warmup {
        let result = await loader.load(warm)
        print("warmup \(warm.absoluteString): \(result.summary)")
        try? await Task.sleep(for: .seconds(options.gap))
    }
    for (index, url) in options.urls.enumerated() {
        if index > 0 { try? await Task.sleep(for: .seconds(options.gap)) }
        let result = await loader.load(url)
        print("\(url.absoluteString): \(result.summary)")
        if let html = result.html, let dir = options.outdir {
            let name = options.api.map { _ in slug(url) + ".json" } ?? slug(url) + ".html"
            let path = (dir as NSString).appendingPathComponent(name)
            try? html.write(toFile: path, atomically: true, encoding: .utf8)
            print("  saved \(path) (\(html.utf8.count) bytes)")
        }
        await loader.clearCaches()
    }
    exit(0)
}
NSApplication.shared.run()
