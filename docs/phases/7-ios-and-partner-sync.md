# Phase 7 - iOS/iPadOS app & partner live sync

Canonical context: `docs/00-vision.md` (product decisions) and `docs/research.md` (verified/unverified findings). This doc is standalone but defers to the vision doc where they disagree.

## 1. Goal

1. Ship Segue on iPhone and iPad, reusing `SegueCore` and `SegueUI`, so the same library is usable on a mic-stand iPad or a phone in a pocket.
2. Keep that library in sync across Mac and iOS through an iCloud Drive folder, with files staying canonical.
3. Let a duo partner's device follow the leader's set live during a gig over the local network, with no internet required.

## 2. Scope / non-goals

**In scope**
- iOS/iPadOS app target (iOS 26+), Personal and App Store schemes mirroring the Mac split.
- Library in an iCloud Drive folder: discovery, download-on-demand, conflict resolution UI, offline guarantees.
- Leader/follower live set sync between Apple devices (Mac <-> iPad/iPhone, any combination), following song **and section/scroll position**.
- Personal modules (audio-to-chart, LRCLIB, URL import) in the iOS Personal scheme (see section 4a).
- Transport behind a port; first adapter chosen by the research ticket in section 4.

**Non-goals**
- Android client (protocol stays open to it; no app).
- Accounts, cloud backend, multi-user editing of the same song at the same time.
- Partner editing the leader's songs or setlist, or requesting songs into the leader's queue (follower is strictly read-only for set state - decided).
- Bluetooth pedal/MIDI parity on iOS beyond what phase 6 code gives for free.

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

### R7.2 - Storage re-check (blocks sync implementation)

The storage decision (files canonical + rebuildable index) explicitly deferred the sync mechanism to this phase. Re-check iCloud Drive folder sync vs CKSyncEngine + GRDB against the current OS:
- iCloud Drive: eviction/dataless behaviour on iOS 26+, NSFileVersion conflict reliability, the 26.2 package-sync regression (does it affect plain folders?).
- CKSyncEngine: what it would cost to keep files canonical (files as export vs source of truth).
Default if nothing new turns up: iCloud Drive folder, as designed below.

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
- **Model size and memory:** large Whisper/Demucs models may exceed comfortable iPhone memory and storage; pick smaller per-device model variants (device-class entry in the model manifest) and analyse with the app in the foreground (no long background processing guarantee).
- **Sandbox:** models download into the app container (Application Support, excluded from iCloud backup); mic via `NSMicrophoneUsageDescription`.
- **URL import:** delivered via the iOS Share extension in the Personal build only.
- All three must be re-validated on iPhone hardware against the phase 5 eval targets; failing devices hide the feature rather than ship a degraded one.

## 5. Library sync design (iCloud Drive)

- Library folder is a **user-picked iCloud Drive folder** (visible in Files, portable), accessed via security-scoped bookmark on each device. First launch on iOS asks the user to pick (or create) the folder; a stale/broken bookmark shows a re-pick prompt and never silently falls back to an empty library. Same layout as Mac: `.cho` + JSON sidecar per song, setlists and gig log as JSON.
- **Discovery:** `NSMetadataQuery` on the ubiquity scope feeds the index; the SQLite index stays a rebuildable projection per device.
- **Coordination:** every read/write goes through `NSFileCoordinator`; library objects adopt `NSFilePresenter` so open editors see external changes.
- **Dataless files:** an evicted file shows in the library with a cloud badge; opening it triggers `startDownloadingUbiquitousItem`. A setlist marked **"Gig ready"** pins all its songs, sidecars and assets locally (download eagerly, warn if any fail). The live view only ever opens fully local files.
- **Conflicts:** detect via `NSFileVersion.unresolvedConflictVersionsOfItem`. Song conflicts get a side-by-side diff UI (keep mine / keep theirs / keep both as copy). Sidecar and setlist JSON use field-level merge where safe (tags union, latest play log append) and fall back to the same UI.
- Gig log is append-only per device (one file per device per gig) to make conflicts impossible by construction.

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
| iCloud offline at gig | No impact: gig-ready pinning means everything is local. |

## 8. Test strategy

Integration-first; unit tests only for tricky pure logic.

- **Protocol integration (primary):** leader and follower engines connected through the in-memory transport with fault injection (drops, delays, reorder, disconnect), deterministic via injected clock and RNG; assert follower state and rendered position after each scenario. The same suite runs against the real adapter chosen by R7.1.
- **Device integration:** Mac leader + iPad follower and iPhone follower on the real adapter: song changes, section/scroll following across different layouts, trusted-device reconnect without code.
- **iCloud E2E:** two devices on a user-picked iCloud Drive folder, edit the same song offline on both, reconnect, resolve via the conflict UI; evict a gig-ready set and confirm pinning re-downloads it; broken bookmark shows the re-pick prompt.
- **Personal modules on iOS:** phase 5 pipeline integration tests on iPhone hardware; App Store iOS archive passes absence checks.
- **Unit (narrow):** sidecar field-level merge rules, `scrollHint` mapping between layouts.
- **Field test:** venue-like setup (busy Wi-Fi, no router) measuring follow latency and reconnect time.
- UI tests for iPhone and iPad live views and the touch visual editor at all size classes, including dark stage theme pixel checks.

## 9. Acceptance criteria

- The same library opens on Mac, iPad and iPhone; an edit on one appears on the others within normal iCloud latency, and no data is lost on a concurrent edit (conflict UI shown).
- A "gig ready" setlist is fully usable in airplane mode on every device.
- The follower follows song changes and section/scroll position in under 500 ms on local Wi-Fi (target from R7.1 spike), recovers from a 30 s disconnect without user action, and never shows an empty screen.
- The follower can show songs it does not have locally via `songPayload`.
- A trusted partner device reconnects with no code; a new device requires the code.
- The visual editor works on iPhone; personal modules run in the iOS Personal build and are absent from the iOS App Store archive.
- Transport adapters are swappable without touching core, proven by the in-memory and one real adapter passing the same test suite.
- Both schemes (Personal, App Store) build and pass tests for iOS.

## 10. Resolved decisions

See `docs/decisions.md`. Still blocked: transport (R7.1) and iCloud Drive vs CKSyncEngine (R7.2).

1. **Follower tracks section/scroll**, not just song - layout-independent `scrollHint`.
2. **Trusted devices remembered** - code only on first pairing.
3. **No partner song requests** - `requestSong` removed; follower is read-only.
4. **Visual editor on iPhone** - touch-adapted, shared chord-placement model with the Mac editor.
5. **Personal modules on iOS** - per-device model variants, foreground analysis, same absence checks.
6. **User-picked iCloud Drive folder** - visible and portable; bookmark failure handling required.
7. **Follower's own transpose/instrument view persists per partner device** between gigs; it never resets to the leader's view.

## 11. Open questions

1. Transport choice and no-router fallback - blocked on R7.1.
2. iCloud Drive folder vs CKSyncEngine - blocked on R7.2 (a user-picked folder makes the iCloud Drive path the default unless R7.2 finds a blocker).
