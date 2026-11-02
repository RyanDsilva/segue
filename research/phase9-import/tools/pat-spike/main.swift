import AppKit
import WebKit

// Cloudflare Research demo origin: answers 401 with a PrivateToken challenge;
// the page reads "Privacy Pass Token ... not presented" when no token came back.
let target = URL(string: "https://demo-pat.research.cloudflare.com/login")!
let storeID = UUID(uuidString: "5E6E0A00-0000-4000-8000-00000000A0A0")!

final class Probe: NSObject, WKNavigationDelegate {
    var view: WKWebView?
    var statuses: [String] = []
    func start() {
        // 1. URLSession, ephemeral, plain (honest UA)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        var req = URLRequest(url: target)
        req.setValue("Segue/1.0 (+https://segue.ryandsilva.dev) PAT-spike", forHTTPHeaderField: "User-Agent")
        URLSession(configuration: cfg).dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(decoding: data ?? Data(), as: UTF8.self)
            let presented = body.contains("not presented") ? "NOT presented" : (body.isEmpty ? "empty" : "no 'not presented' marker")
            print("URLSession: status \(code), err \(String(describing: err)), token \(presented)")
            DispatchQueue.main.async { self.web() }
        }.resume()
    }
    func web() {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        conf.preferences.inactiveSchedulingPolicy = .none
        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: conf)
        v.navigationDelegate = self
        view = v
        v.load(URLRequest(url: target))
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("TIMEOUT"); exit(2) }
    }
    func webView(_ w: WKWebView, decidePolicyFor r: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if let h = r.response as? HTTPURLResponse { statuses.append("\(h.statusCode) \(h.url?.path ?? "")") }
        return .allow
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        w.evaluateJavaScript("document.body.innerText") { res, _ in
            let text = (res as? String) ?? ""
            let line = text.split(separator: "\n").first { $0.contains("Token") } ?? "?"
            print("WKWebView (hidden, dataStore(forIdentifier:)): main-frame responses \(self.statuses); page says: \(line)")
            exit(0)
        }
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: any Error) { print("didFail \(e)"); exit(3) }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: any Error) { print("didFailProvisional \(e)"); exit(3) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let p = Probe()
p.start()
app.run()
