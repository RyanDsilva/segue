# Phase 2 adversarial review (2026-10-17)

Independent read-only review of cd2459f^..64638c3. Most findings reproduced with probes; "inspection" marks the rest.

| # | Sev | Finding | Fix |
|---|---|---|---|
| 1 | blocker | Failed show-file write: engine advances, stage does not; next press skips a song on screen; notice cleared on next command | apply `controller.state` in catch; persistent "show not saving" banner until a write succeeds; same for prefs/scroll failures |
| 2 | high | Reorder "Save to setlist" overwrites setlist edits made after show start (entries rebuilt from start snapshot) | merge order + inserted rows into the current setlist; warn/confirm if it changed |
| 3 | high | Play Now of the current song (or twice) duplicates it and leaves a ghost pending item | no-op when target is current; match current first |
| 4 | high | Key auto-repeat fires `next` ~30/s (no isARepeat filter) | ignore repeats for show-scope commands |
| 5 | high | v3 sidecars missing any key open read-only/unreadable (strict decode on current path) | decode current via lenient PartialSidecar |
| 6 | med | Stale scroll flush can write the old song's position onto the new song | pass ShowItemID; drop if not current |
| 7 | med | Resume after crash inflates first song duration (gap counted) | `.resumed` restarts the item clock |
| 8 | med | Quick search Enter acts on previous query's results | track results query; defer Enter |
| 9 | med | Two app instances can resume the same show and clobber it | single-instance guard or per-library lock + claim token |
| 10 | med | Cmd-Q / Cmd-W on stage quit without confirm; end Shortcut never runs (also on stale close) | route terminate through end-confirm; run end Shortcut on stale close |
| 11 | med | Stage blank when current song has no snapshot | "Song unavailable - press → to continue" |
| 12 | med | Devanagari vertical metrics measured on Latin font; matras can overlap chord band; audit blind | per-line ink extents; geometry/pixel test on live-devanagari |
| 13 | med | Switching library mid-show orphans session, keep-awake, stage window | stop + close first, or block while live |
| 14 | low | Autoscroll never settles; TimelineView ticks forever; A needs two presses at end | call settle(at:) |
| 15 | low | Autoscroll on wall clock (NTP/sleep jumps) | monotonic suspending clock |
| 16 | low | Per-song prefs saves race (unordered Tasks); poll-based test flake | serialize latest-value saves |
| - | nits | persist() acks before landed; refreshState re-read after await; scroll durability ~1.5 s vs 1 s; reorder reviews in memory only; clock skew in launchCheck; bindings.json schemaVersion ignored; short-lived notices | see review notes |
| - | gaps | no tests for 100 ms advance render, LiveSession write failure, play-now idempotency, key repeat, stale search, no-snapshot current, v3 partial sidecar, review vs edited setlist, library switch leak, real-time/sleep scroll | add with fixes |
