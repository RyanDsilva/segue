# Phase 7 sync research - R7.1 transport, R7.2 storage (2026-10-17)

Primary sources only. **V** = VERIFIED (source given), **U** = UNVERIFIED. Local SDK = Xcode 26.6 / SDK 26.5 at `/Applications/Xcode.app/.../<Platform>.sdk` (Xcode 27 is not installed, so 27-era attributes cannot be read locally). Doc JSON fetched from `developer.apple.com/tutorials/data/documentation/...`.

## R7.1 - Partner-sync transport

### MultipeerConnectivity (MPC)
- **Deprecated.** Doc page banner: "Multipeer Connectivity is deprecated. Migrate any code using this framework to the Network framework" (V, developer.apple.com/documentation/multipeerconnectivity). TN3213 (2026-07-14): "Xcode 27 deprecates the entire Multipeer Connectivity framework" (V, developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework). TN3151 rev 2026-07-23 repeats it (V). Quinn (DTS), July 2026: "formally deprecated in Xcode 27 beta ... not something I recommend for new products" (V, developer.apple.com/forums/thread/836723).
- The installed 26.5 SDK headers carry **no** deprecation attribute yet - only `NS_CLASS_AVAILABLE(10_10, 7_0)` (V, `MacOSX.sdk/.../MultipeerConnectivity.framework/Headers/MCSession.h:83`). Claim "deprecated in Xcode 27" is therefore confirmed by docs, not by the local SDK.
- Peer limit: exposed as `kMCSessionMaximumNumberOfPeers` (V, `MCSession.h:36`); the value "8" is U (not in header). Moot - MPC is out.

### Network.framework (the replacement)
- New Swift API `NetworkListener`, `NetworkConnection`, `NetworkBrowser`: `@available(macOS 26.0, iOS 26.0, ...)` on both platforms (V, `Network.swiftmodule/arm64e-apple-{macos,ios}.swiftinterface` lines 137, 1072, 1724). Built-ins include `.bonjour(name:type:domain:txtRecord:)` listener provider (l.1133), `TLV` and `Coder<..., .json>` message framing (l.1554-1680), `WebSocket` (l.1600). Older `NWListener/NWBrowser/NWConnection` are **not** deprecated in SDK 26.5 (V, only 5 `deprecated` attributes in the interface, none on these).
- **Apple peer-to-peer Wi-Fi (AWDL)**: opt in with `includePeerToPeer` / builder `peerToPeerIncluded(_:)`; available macOS 10.14+, iOS 12+, no deprecation (V, SDK l.1372, 2496; `Network.framework/Headers/parameters.h:687-724`; doc JSON for `nwparameters/includepeertopeer` has no deprecation). "Only works between Apple devices" (V, TN3151). Off by default; "can reduce network performance ... stop browsing ... before you kick off the connection" (V, TN3213 "Enable peer-to-peer Wi-Fi").
- **"AWDL phase-out because of EU DMA" - not supported by primary sources.** The EC specification decision requires "Wi-Fi Aware 4.0 in iOS 26. Wi-Fi Aware 5.0 in the next iOS release..." and does not mention AWDL (V, digital-markets-act.ec.europa.eu/developer-portal/interoperability/apple-specification-proceedings-interoperability-connected-devices-and-request-based-process_en). Apple's July 2026 technotes still document AWDL as supported. Treat AWDL as live but Apple-only, with long-term risk (U).
- Mac <-> iOS over AWDL with third-party NWListener: API exists on macOS (V); real-world reliability, latency, peer ceiling: **U - spike required**. Apple documents no peer ceiling for Network.framework (absence V; practical limit U).
- Security: TLS-PKI via `TLS().localIdentity(...)` with custom trust evaluation; TLS-PSK only on the old `NWConnection` API, no QUIC/TLS 1.3; Apple has no API to mint an identity - use `swift-certificates` (V, TN3213 "Plan for security").
- Reconnection is the app's job. TCP keepalive is **off** and send timeout **infinite** by default; use `keepalive(idleTimeInSeconds:count:intervalInSeconds:)` and `retransmitConnectionDropTime(_:)`. QUIC idle timeout defaults to 30 s (V, TN3213 "Overriding protocol defaults"). Deduplicate connections by a self-generated peer UUID; client-server architecture recommended (V, TN3213).
- Service type for TCP/WebSocket is `_x._tcp`, for QUIC `_x._udp` (V, TN3213 "About service types").

### Wi-Fi Aware
- **iOS/iPadOS 26 only. Not macOS.** macOS SDK ships `WiFiAware.framework` but every symbol is `@available(macOS, unavailable)` (V, `MacOSX.sdk/.../WiFiAware.swiftmodule/arm64e-apple-macos.swiftinterface`: 56 `macOS, unavailable`). The docs list Mac Catalyst 26.0, but the iOS interface marks it `@available(macCatalyst, unavailable)` (V, `arm64e-apple-ios.swiftinterface:14`) - SDK wins.
- Devices: iPhone 12+, iPad 10th gen+, iPad Air 4+, iPad Pro 11" 3rd gen+, 12.9" 5th gen+, iPad mini 6+ (V, developer.apple.com/documentation/wifiaware).
- Requires entitlement `com.apple.developer.wifi-aware` with `Publish`/`Subscribe` and `WiFiAwareServices` Info.plist key (V, docs for both). Devices must be **paired** first via DeviceDiscoveryUI or AccessorySetupKit (V, sample "Building peer-to-peer apps", wifiaware/building-peer-to-peer-apps). Runtime limits via `WACapabilities.maximumConnectableDevices` (V, SDK l.127). Wi-Fi Aware + QUIC unsupported before iOS 27 (V, TN3213).
- Standards-based (NAN), so it is the plausible Android door for no-router use (Android support for NAN is U here).

### DeviceDiscoveryUI
- iOS 26 / tvOS 16; `@available(macOS, unavailable)` (V, `iPhoneOS.sdk/.../DeviceDiscoveryUI.swiftmodule/arm64e-apple-ios.swiftinterface:45-49`). Not usable on the Mac leader.

### Sandbox and privacy
- macOS: `com.apple.security.network.server` + `.network.client` ("Apps using UDP usually require both") (V, docs for network.server; Quinn, thread 836723).
- `NSLocalNetworkUsageDescription` (macOS 11+/iOS 14+ key) and `NSBonjourServices` listing `_segue._tcp` (V, doc JSON; TN3179). Local network privacy enforced on iOS 14+, **macOS 15+** (V, TN3179). Bonjour register/browse/resolve all need the privilege; multicast entitlement is **not** needed for declared service types, and not on macOS at all (V, TN3179). DeviceDiscoveryUI needs no local network access (V, TN3179). A Bonjour op with peer-to-peer enabled can trigger the alert even "off Wi-Fi" (V, TN3179 "iOS considerations").

### Comparables
- forScore Cue: "iOS uses a combination of Bluetooth and WiFi ... then create an ad hoc network between them"; works without a local Wi-Fi network (V, forscore.co/kb/cue-connections/). This is MPC-style behaviour; that it is MPC is U.
- OnSong Connect: "control ... other compatible apps on your local network using WiFi" (V, onsongapp.com/docs/1.999/features/connect). Infrastructure LAN only; no no-router mode documented.

## R7.2 - iCloud Drive folder vs CKSyncEngine

### User-picked iCloud Drive folder on iOS
- Picking a folder via `UIDocumentPickerViewController` (iOS 13+) yields a security-scoped URL that "lets your app recursively access the directory ... including any new items"; save it as a bookmark and resolve it later; use a file coordinator for reads/writes; users can revoke in Settings > Privacy > Files and Folders, so expect `startAccessingSecurityScopedResource()` to fail (V, developer.apple.com/documentation/uikit/providing-access-to-directories). Spec's re-pick prompt is required, confirmed.
- **Change notifications: `NSMetadataQuery` is not reliable for this case.** `NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope` is documented for out-of-container docs (V, `Foundation.framework/Headers/NSMetadata.h:108`), but DTS told a developer it "doesn't behave as documented" (FB9631965; returns nothing for imported folders) (V, developer.apple.com/forums/thread/689468). Subdirectory changes in a picked folder not detected, iOS 18.4.1 (V that it was reported, unanswered: forums/thread/783958). The other ubiquity scopes cover only the app's own container (V, `NSMetadata.h:106-107`).
- **`NSFilePresenter` on the folder works** (`presentedSubitemDidChange(at:)` is the reliable callback) (V as developer report in thread 689468, not Apple-confirmed). On iOS a presenter must be removed on background and re-added on foreground or the app may be killed (V, NSFileCoordinator docs "File Presenters and iOS"). So changes while backgrounded are **missed** - a foreground rescan is mandatory.
- Dataless files: `NSURLUbiquitousItemDownloadingStatusKey` (NotDownloaded/Downloaded/Current) and `startDownloadingUbiquitousItem(at:)` exist on iOS 7+/5+ (V, `NSURL.h:383-401`, `NSFileManager.h:307`). That they work on security-scoped URLs outside the container is U (spike).
- Conflicts: `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` (V, doc). Whether iCloud Drive produces NSFileVersion conflicts for a third-party-edited file in a user folder, rather than "name 2.cho" duplicates, is U (spike).
- 26.2 package regression: affects **packages only**, plain files/folders synced; fixed in macOS 26.3 (V, forums/thread/810671, FB21363976). Does not affect a plain `.cho` + JSON folder.

### CKSyncEngine
- Available iOS 17 / macOS 14; app must persist the engine's opaque state; sync schedule "indeterminate", force with `fetchChanges`/`sendChanges` (V, developer.apple.com/documentation/cloudkit/cksyncengine-5sie5).
- 2026 reliability: iOS 26.4 dropped CloudKit pushes so running apps saw no remote changes (affects CKSyncEngine), fixed in 26.5 beta (V, forums/thread/820550, DTS Ziqiao Chen); iOS/macOS 26.5 pending changes added during event handling not sent until relaunch, open as of June 2026 (V, forums/thread/829402).
- Files-canonical cost: records become a second source of truth; we would own file<->record mapping, tombstones, conflict merge and a records-to-files writer on every device, and lose "visible in Files, portable". Files could only be an export.

## Recommendation

**R7.1:** One adapter: **Network.framework Swift API (`NetworkListener`/`NetworkBrowser`/`NetworkConnection`), TCP + TLS + `TLV` length-prefixed JSON frames, Bonjour `_segue._tcp`, with `peerToPeerIncluded(true)` on listener and browser.** Leader = server, followers = clients. That single stack covers venue/home Wi-Fi and router-less Mac<->iPad<->iPhone via AWDL. Ranked:
1. Network.framework + Bonjour + AWDL (above) - only option spanning Mac and iOS without a router.
2. Fallback: same adapter over an iPhone Personal Hotspot as an ad hoc router (U - spike Bonjour on hotspot).
3. Later/optional: Wi-Fi Aware adapter for iOS<->iOS (and the Android door), never Mac.
Rejected: MPC (deprecated).
Android door: keep the wire protocol as plain TCP+TLS with length-prefixed JSON and standard mDNS/DNS-SD (no AWDL- or Apple-type dependence); a WebSocket framing variant can be added if Android needs it. Wi-Fi Aware is the standards-based no-router path for Android later.

**R7.2:** Keep the **user-picked iCloud Drive folder** (default stands). CKSyncEngine adds a second source of truth and has had two 2026 regressions. But change discovery must change: NSFilePresenter + rescan, not NSMetadataQuery.

## Spec impacts (phase 7 doc)
1. Section 5 "Discovery": replace `NSMetadataQuery` with an `NSFilePresenter` on the library root (`presentedSubitemDidChange`) **plus a full rescan** (mtime/size/contentHash diff) on launch, on foreground, on bookmark resolve; NSMetadataQuery at most a hint.
2. iOS: remove presenters on background, re-add on foreground (Apple requirement).
3. Conflicts: detect both `NSFileVersion` conflicts and Finder-style duplicate names (`name 2.cho`) until the spike proves which one iCloud Drive produces.
4. R7.2 spike list: `startDownloadingUbiquitousItem` on a security-scoped URL; conflict-version generation; subfolder change delivery on iOS 26.
5. Section 6 transport: name the first adapter (above); set TCP keepalive + `retransmitConnectionDropTime`; follower **stops browsing once connected** and restarts on disconnect; reconnect/backoff lives in the adapter; dedupe by peer UUID.
6. Pairing: generate a per-device identity (`swift-certificates`), first pairing via short code, "trusted device" = pinned peer certificate fingerprint, mutual TLS after.
7. Entitlements/plists: macOS `network.server` + `network.client`; both platforms `NSLocalNetworkUsageDescription`, `NSBonjourServices = [_segue._tcp]`; no multicast entitlement. Prompt for local network at "Start session", not app launch; handle denial with a settings deep-link.
8. R7.1 spike still owed: latency (<500 ms target), reconnect, 3+ followers, AWDL Mac<->iPhone with no router, hotspot fallback, busy venue Wi-Fi.
9. `research.md` partner-sync bullets: MPC deprecation confirmed; Wi-Fi Aware not on macOS; AWDL phase-out claim unsupported; peer ceiling "~8" was MPC-only.
