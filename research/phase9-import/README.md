# research/phase9-import - P9-4 corpus, spikes and eval

Working folder for workstream P9-4 (`docs/phases/9-workstreams/P9-4-lyrics-and-url-import.md`, Personal build only). Fetched pages, recorded responses and gold files contain copyrighted lyrics: they live in gitignored folders here and are never committed (spec 16.1). Only the lyric-redacted fixtures under `Packages/SeguePersonalModules/Tests/Fixtures/web/` are committed (spec 16.2).

## Spikes

### a0 - Private Access Token spike (R183), 2026-11-01

Question: does a sandboxed third-party Mac app's hidden `WKWebView` receive Apple's Private Access Tokens, so a Cloudflare managed challenge can pass with no interaction?

Tool: `tools/pat-spike/run.sh` (manual, live network, two requests). It builds a tiny app signed with exactly the Personal build's network entitlements (`com.apple.security.app-sandbox`, `com.apple.security.network.client`), then loads Cloudflare Research's PAT demo origin `https://demo-pat.research.cloudflare.com/login` (it answers HTTP 401 with `WWW-Authenticate: PrivateToken challenge=..., token-key=...`; a client that presents a token gets the page without the "not presented" mark) once with an ephemeral `URLSession` and once in a hidden `WKWebView` (no window, `.prohibited` activation policy, `inactiveSchedulingPolicy = .none`) on a dedicated `WKWebsiteDataStore(forIdentifier:)`.

Setup: macOS 26.6.2, Xcode 27.1, Apple Account signed in (iCloud, not a managed account).

| Client | Result |
|---|---|
| Sandboxed app, `URLSession` ephemeral | 401, token not presented |
| Sandboxed app, hidden `WKWebView`, `dataStore(forIdentifier:)` | 401, token not presented |
| Same binary unsandboxed, `URLSession` and hidden `WKWebView` | 401, token not presented (both) |
| **Safari 26 (baseline)**, same page | **token not presented** |

Verdict: **no token was issued to any client on this Mac, Safari included**, so the spike cannot yet tell whether an app's web view would get one. The likely cause is the system setting System Settings > [Apple Account] > Sign-In & Security > **Automatic Verification** being off (it gates Private Access Tokens for every client); it may also be that Apple's attester does not serve this research issuer (`pp-issuer-production.research.cloudflare.com`). Until the Safari baseline passes, plan on Open Here being needed whenever a cold or reset store meets a managed challenge. Nothing in the loader depends on the answer (spec 8.6).

To finish the spike (Ryan): turn on Automatic Verification if it is off, open the demo page in Safari and check that it no longer reads "not presented", then run `research/phase9-import/tools/pat-spike/run.sh` and add the two app rows here. The spike's sandbox container `~/Library/Containers/dev.ryandsilva.segue.patspike` holds only an empty WebKit store and can be moved to the Trash from Finder.
