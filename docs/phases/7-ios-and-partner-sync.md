# Phase 7 - iOS/iPadOS app & partner live sync

Canonical context: `docs/00-vision.md` (product decisions) and `docs/research.md` (verified/unverified findings). This doc is standalone but defers to the vision doc where they disagree. Roadmap: the last phase by the orchestrator's default (`docs/release/decisions.md` R138; Ryan has not ranked it against phase 5). iCloud Drive library sync and its conflict UI were removed (R132) and replaced by a Files-app library folder (R134).

## 1. Goal

1. Ship Segue on iPhone and iPad, reusing `SegueCore` and `SegueUI`, so the same library is usable on a mic-stand iPad or a phone in a pocket.
2. Open the library on iOS from a folder the user picks in the Files app (any provider), reading the ChordPro files directly; files stay canonical and Segue has no sync engine of its own (R134).
3. Let a duo partner's device follow the leader's set live during a gig over the local network, with no internet required.

## 2. Scope / non-goals

**In scope**
- iOS/iPadOS app target (iOS 26+), Personal and App Store schemes mirroring the Mac split.
- Library from a Files-app folder (iCloud Drive, Dropbox, On My iPhone or any other provider), picked by the user (R134).
- Leader/follower live set sync between Apple devices (Mac <-> iPad/iPhone, any combination), following song **and section/scroll position**.
- Personal modules (LRCLIB, URL import) in the iOS Personal scheme (see section 4a).
- **N5 Share by file** (R136): AirDrop or Share a setlist plus its songs as one file. Spec not written yet.
- Transport behind a port; first adapter chosen by the research ticket in section 4.

**Non-goals**
- Android client (protocol stays open to it; no app).
- Accounts, cloud backend, multi-user editing of the same song at the same time.
- A Segue sync engine, iCloud-specific sync or a conflict-resolution UI (R132, R134): the file provider syncs the folder.
- Partner editing the leader's songs or setlist, or requesting songs into the leader's queue (follower is strictly read-only for set state - decided).
- MIDI parity on iOS beyond what phase 6 code gives for free (Bluetooth HID pedals are removed, R132).

## 3. Mandatory tickets before build

### R7.1 - Partner-sync transport research (blocks transport choice)

Verify at primary source (Apple docs, WWDC sessions, SDK headers) the claims `research.md` marks UNVERIFIED:
- Is MultipeerConnectivity deprecated (claimed "Xcode 27")?
- Wi-Fi Aware: which platforms and devices (claimed iPhone 12+); is it available on macOS at all?
- AWDL / `includePeerToPeer` status (claimed phase-out because of the EU DMA).
- Practical peer ceiling (claimed ~8) and latency of Network.framework peer-to-peer.
- Bonjour + TCP/WebSocket on a venue Wi-Fi vs no-router scenarios; local network privacy prompt behaviour.
- How forScore Cue and OnSong Connect actually transport (for comparison).

Output: a ranked transport choice for Mac<->iOS with a no-router fallback, plus a spike measuring latency and reconnect on real devices. Until it lands, the transport stays a port with no committed adapter.

### R7.2 - Storage re-check (superseded)

Superseded by R134: there is no Segue sync mechanism to choose. The iOS app reads a user-picked Files-app folder; the earlier iCloud Drive vs CKSyncEngine outcome (`docs/decisions.md`, Phase 7 research outcomes) no longer applies.

## 4. Platform adaptation

| Surface | iPhone | iPad | Mac (unchanged) |
|---|---|---|---|
| Library / editor | List + detail push; **text and visual editors** (visual editor adapted to touch: tap a syllable to place a chord, drag to move) | Split view; both editors | Both |
| Live view | Portrait single column, larger auto-fit floor, swipe = next/prev, tap edges = scroll | Landscape auto-fit columns like Mac; portrait 1-2 columns | As built |
| Next-song footer | Compact one-line | As Mac | As built |
| Keep awake | `isIdleTimerDisabled` while live; Focus guidance (apps cannot force Do Not Disturb) | Same | As built |
| Per-song zoom memory | Stored per device class (phone/tablet/mac) in the sidecar so a Mac tweak does not wreck the phone view | | |

`SegueUI` gets size-class-driven layouts; no forked view hierarchies unless a view genuinely differs (live view gestures). The visual editor is built on TextKit 2 in AppKit on the Mac (phase 1); on iOS it needs a UIKit TextKit 2 host (`UITextView`) sharing the same layout/chord-placement model, so phase 1 must keep that model platform-neutral.

### 4a. Personal modules on iOS

The iOS Personal scheme links `Packages/SeguePersonalModules` exactly like the Mac one, and the same absence checks run on the iOS App Store archive. Implications to design for:
- **URL import:** delivered via the iOS Share extension in the Personal build only.
- **LRCLIB search:** the same `LyricsSource` implementation as the Mac.
- **Custom model setting (R97):** stays Mac-only; not offered on iOS (R143).

## 5. Library source (Files-app folder, R134)

- The library is a **folder the user picks in the Files app** (folder picker), from any provider: iCloud Drive, Dropbox, On My iPhone or others. It is accessed through a security-scoped bookmark; a stale or broken bookmark shows a re-pick prompt and never silently falls back to an empty library. Same layout as the Mac: `.cho` + JSON sidecar per song, setlists and gig log as JSON.
- The app reads and writes the ChordPro files and sidecars in that folder directly. The SQLite index stays a rebuildable projection per device.
- **No Segue sync engine and no conflict UI.** Moving changes between devices is the file provider's job; whatever the provider leaves in the folder is what the library shows.
- **Gig ready** (R143): before a gig the app eagerly downloads the setlist's song files and sidecars from a cloud-provider folder and keeps them pinned offline (with a visible ready / not ready state per setlist), rather than relying on the provider's own offline setting.
- **Gig log stays one file per device per gig** (R143), so two devices never write the same file.

## 6. Partner live sync design

### Roles
- **Leader:** owns the live set state. One per session.
- **Follower:** mirrors it. Read-only for set state; may change its own zoom, transpose display and instrument view locally.

### State model
The leader holds a single `LiveSetState` and bumps a monotonic `version` on every change. It sends **full snapshots**, never deltas, so a follower that missed anything just applies the latest one.

```
LiveSetState {
  sessionId: ULID
  version: UInt64            // monotonic per session
  setlist: [SongRef]          // ordered, with skipped/played flags
  requestQueue: [SongRef]
  current: { songRef, section?, scrollHint? }
  leaderClock: timestamp
}
SongRef { songId, title, contentHash, key, capo }
```

### Messages (transport-agnostic, JSON or length-prefixed binary)
- `hello { protocolVersion, deviceName, role }`
- `snapshot { LiveSetState }` - sent on every change and as a heartbeat every ~2 s.
- `songPayload { songId, contentHash, choText, sidecarSubset }` - sent on request when the follower lacks the song or its hash differs.
- `ack { version }` (optional, for the leader's peer status UI).
- `bye {}`.

Followers apply a snapshot only if `version >` the last applied one (idempotent, order-tolerant). The protocol is plain messages over a byte stream with no Apple-only types, so an Android client could speak it later.

### Transport port
`LiveSyncTransport` exposes `advertise`, `discover`, `connect`, `send`, and an `incoming` stream. Adapters come from R7.1, for example Network.framework/Bonjour (TCP or WebSocket), a peer-to-peer variant, and an in-memory adapter for tests. Pairing: the first connection uses a short code shown on the leader (to avoid joining a stranger's session at an open mic); after that, both sides **remember the device as trusted** (stored per device, revocable in settings) and reconnect without a code.

### Section/scroll following
`current.section` and `current.scrollHint` are authoritative. `scrollHint` is layout-independent (section index + line index within the song AST + fraction), never pixels, because leader and follower fit the song differently (Mac columns vs iPhone single column). The follower scrolls to keep that line visible; while the follower user is touching the screen, following pauses and a "re-follow" chip appears.

## 7. Failure modes on stage

The follower screen must **never blank, jump unexpectedly, or show a spinner over the chart**.

| Failure | Behaviour |
|---|---|
| Follower loses connection | Keep showing the current song; small amber "disconnected" chip; local navigation unlocked; auto-reconnect with backoff; on reconnect apply the latest snapshot. |
| Leader app crashes/quits | Same as above; follower can take over as standalone. |
| Song missing on follower | Request `songPayload`; meanwhile show title/key/capo card (never empty). Cache received songs in a session folder, offer to import after the gig. |
| Song differs (hash mismatch) | Show leader's version (from payload), badge "leader's version". |
| Stale/duplicate/out-of-order snapshot | Ignored by the version check. |
| Venue Wi-Fi blocks peer traffic | Fall back to the no-router transport chosen in R7.1. |
| Cloud provider offline at gig | Open question 3 (offline guarantees for a cloud-provider folder). |

## 8. Test strategy

Integration-first; unit tests only for tricky pure logic.

- **Protocol integration (primary):** leader and follower engines connected through the in-memory transport with fault injection (drops, delays, reorder, disconnect), deterministic via injected clock and RNG; assert follower state and rendered position after each scenario. The same suite runs against the real adapter chosen by R7.1.
- **Device integration:** Mac leader + iPad follower and iPhone follower on the real adapter: song changes, section/scroll following across different layouts, trusted-device reconnect without code.
- **Files-folder E2E:** pick a library folder in the Files app, open songs and setlists from it, see an edit made on the Mac after the provider syncs it; a broken bookmark shows the re-pick prompt.
- **Personal modules on iOS:** phase 5 pipeline integration tests on iPhone hardware; App Store iOS archive passes absence checks.
- **Unit (narrow):** `scrollHint` mapping between layouts.
- **Field test:** venue-like setup (busy Wi-Fi, no router) measuring follow latency and reconnect time.
- UI tests for iPhone and iPad live views and the touch visual editor at all size classes, including dark stage theme pixel checks.

## 9. Acceptance criteria

- The same library folder opens on Mac, iPad and iPhone through the Files app; an edit on one appears on the others once the file provider has synced it.
- The follower follows song changes and section/scroll position in under 500 ms on local Wi-Fi (target from R7.1 spike), recovers from a 30 s disconnect without user action, and never shows an empty screen.
- The follower can show songs it does not have locally via `songPayload`.
- A trusted partner device reconnects with no code; a new device requires the code.
- The visual editor works on iPhone; personal modules (LRCLIB, URL import) run in the iOS Personal build and are absent from the iOS App Store archive.
- Transport adapters are swappable without touching core, proven by the in-memory and one real adapter passing the same test suite.
- Both schemes (Personal, App Store) build and pass tests for iOS.

## 10. Resolved decisions

See `docs/decisions.md` and `docs/release/decisions.md` R132-R138 and R143. R7.1 (transport) is resolved in `docs/decisions.md` (Phase 7 research outcomes); R7.2 is superseded by R134.

1. **Follower tracks section/scroll**, not just song - layout-independent `scrollHint`.
2. **Trusted devices remembered** - code only on first pairing.
3. **No partner song requests** - `requestSong` removed; follower is read-only.
4. **Visual editor on iPhone** - touch-adapted, shared chord-placement model with the Mac editor.
5. **Personal modules on iOS** - same absence checks (audio-to-chart and its model variants removed, R132).
6. **User-picked Files-app folder** (R134, replacing the user-picked iCloud Drive folder) - any provider, no Segue sync engine, no conflict UI; bookmark failure handling required.
7. **Follower's own transpose/instrument view persists per partner device** between gigs; it never resets to the leader's view.
8. **Gig ready kept** (R143) - eager download and offline pinning of a setlist's files from a cloud-provider folder.
9. **One gig-log file per device per gig** (R143).
10. **Custom model setting (R97) is Mac-only** (R143).

## 11. Open questions

1. Transport choice and no-router fallback - resolved by R7.1 in `docs/decisions.md` (Network.framework, TCP + TLS, Bonjour, peer-to-peer Wi-Fi).
2. iCloud Drive folder vs CKSyncEngine - moot (R134).
3. Offline guarantees for a cloud-provider library folder - resolved by R143: keep "Gig ready" (download a setlist's files eagerly before a gig and pin them offline).
4. Gig log files - resolved by R143: keep one file per device per gig.
5. Custom model setting (R97) on iOS - resolved by R143: Mac-only.
