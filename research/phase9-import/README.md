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

## Layout

| Path | Tracked | What |
|---|---|---|
| `urls.tsv` | yes | Every page, search page and LRCLIB query of the corpus (site, kind, lang, url, note) |
| `tools/pat-spike/` | yes | Step a0's Private Access Token spike |
| `tools/wkfetch/` | yes | The hidden WebKit loader as a command-line research tool, plus `import-rules.json` (the same ad and tracker list as `ImportContentRules.swift`) |
| `pages/<site>/` | no | Chart pages (`ug`, `chordie`, `echords`, `generic`) |
| `search/<site>/` | no | Results pages (UG HTML, E-Chords `/api/search` JSON, Chordie discovery pages) |
| `lrclib/` | no | Recorded `/api/search` responses |
| `gold/` | no | Hand-written expected `.cho` per page |
| `logs/` | no | Collector and spike logs |
| `.build/bakeoff/` | no | The bake-off's captures and harness (pages copied into `pages/` in step a3) |

`scripts/collect-import-corpus.sh [site...]` fetches whatever in `urls.tsv` is not saved yet.

### a3 - hidden WebKit loader spikes, 2026-11-01

`tools/wkfetch` on E-Chords (plain requests are hard-blocked there), 5 s or more between loads, one load per run, n = 1 per row. "Cold" is a fresh `dataStore(forIdentifier:)` UUID; memory is the peak RSS of WebKit's WebContent, Networking and GPU processes minus the idle baseline (~15 MB).

| Case | Main frame | Result | Time | Memory |
|---|---|---|---|---|
| Cold, hidden view (no window, `.prohibited`, `inactiveSchedulingPolicy = .none`) | 403 `cf-mitigated: challenge`, then 200 | passed on its own, no `cType` read | 2.3 s | ~470 MB |
| Cold, real window ordered behind | 403 challenge, then 200 | passed | 2.0 s | ~607 MB |
| Cold, visible frontmost window | 403 challenge, then 200 | passed | 2.1 s | ~640 MB |
| Cold, hidden, **sandboxed** (app-sandbox + network.client only) | 403 challenge, then 200 | passed: no new entitlement needed | 2.6 s | ~508 MB |
| Warm store, hidden, no rule list | 200 | page | 1.97 s | ~261 MB |
| Warm store, hidden, ad and tracker rule list | 200 | page | 0.81 s | ~190 MB |

Findings: on 2026-11-01 E-Chords' managed challenge cleared on its own in about 2 s for a cold store in every hosting mode, so the hidden view stays as specced (8.6) and no window is needed; the bake-off's 25 s non-clearing case did not recur (it followed ~10 loads in 15 minutes). The sandbox changes nothing. The rule list cut load time by about 60% and peak memory by about 70 MB on a warm load. Peak memory while a cold view clears a challenge is higher than the bake-off measured (~470-640 MB against 250-330 MB), still zero at rest because the view is torn down 30 s after use; on the 8 GB target that peak is the number to watch. No result changes 8.6.

### a3 - collection, 2026-11-01

- Search pages: 10 UG (`search.php`, plain requests, all 200), 10 E-Chords (`/api/search` JSON read inside the hidden view, 1.4-3.2 s each, no challenge), 10 Chordie discovery pages.
- LRCLIB: 35 queries listed (20 Hindi including 5 deliberate misspellings, 15 English; 12 from the bake-off); 33 recorded; 2 still answered 503 after 5 retries (`tum hi hoo`, `country roads`), the retry policy's failure case.

### a7 - offline eval (`make eval-import`), first run 2026-11-01

Gold (`gold/<slug>.json`, gitignored) is drafted by `tools/gold-draft.py` independently of the Swift readers (fields from each site's structured data, chords from the page's own chord markup, lyric words from its lyric lines) and corrected by hand in `tools/gold-overrides.json` (tracked: field values only, no lyrics). Generic pages carry fields plus a minimum chord and lyric-word count, since no full transcription is kept. A page passes per spec 16.3 (title, artists, album, key when given, capo, lyric words >= 99%, chord F1 >= 98%, no junk line left).

| Reader | Pass | Target |
|---|---|---|
| UG | 7/15 (47%) | >= 95% |
| E-Chords | 4/15 (27%) | >= 95% |
| Chordie | 2/15 (13%) | >= 95% |
| Generic | 6/15 (40%) | >= 80% |
| Silent wrong charts | 6 | 0 |

Not yet meeting the targets. Most lyric misses trace to the drafted gold (credit and note lines, repeated sections), not the readers: the converted charts read right where checked by eye. The gold is reviewed next with the local review tool (`make review-gold`), then the readers are fixed against it.

### a8 - canary (`make import-canary`), 2026-11-01

Live: one known page per reader fetched (UG and Chordie plain, E-Chords through `tools/wkfetch`, a generic page plain) and read by the Personal build's readers, plus one LRCLIB search. First run: UG, Chordie, E-Chords, generic and LRCLIB all PASS. The E-Chords load uses the research loader, not the app's `WebKitPageLoader`, whose live path is exercised in the hands-on walk.

#### Against Ryan's reviewed gold (2026-11-01, 19 UG and E-Chords pages reviewed in `make review-gold`)

| Reader | Pass (all) | Pass (reviewed) | Silent wrong (all / reviewed) |
|---|---|---|---|
| UG | 13/15 (87%) | 13/15 | 0 / 0 |
| E-Chords | 6/15 (40%) | 4/4 | 0 / 0 |
| Chordie | 2/15 (13%) | none reviewed | 1 / - |
| Generic | 6/15 (40%) | none reviewed | 4 / - |

Pages not yet reviewed are scored against the scripted drafts, which miss credit and note lines and repeats, so their numbers can't be trusted until they are reviewed. The two UG misses left are a performance note sung as a lyric line ("Keep repeating these 2 chords till the end") and a parenthesised optional chord, "(G)", whose line the paste pipeline reads as lyrics.
