# Phase 9 workstreams

Phase 9 builds what the v1.0 App Store release adds before submission (R176). Every spec's questions are closed: R177 (iCloud sync in v1.0), R178 (P9-1, P9-2, P9-3), R179 (P9-4, P9-5, P9-6) and R180 (E2E in a local Tart VM, which every session's E2E runs use). The rulings are in [`docs/release/decisions.md`](../../release/decisions.md), R176-R180.

## Specs

| Spec | One line |
|---|---|
| [P9-1 PDF export](P9-1-pdf-export.md) | Single chart, setlist and library-selection songbooks, print and the in-app preview, with the Bass and Lyrics parts and medleys flowing on. |
| [P9-2 Singer view](P9-2-singer-view.md) | Lyrics only with chords, song notes and slot notes hidden: the stage `V` toggle, the previews, printed lyric sheets and a Singer Screen on a second display. |
| [P9-3 Medleys](P9-3-medleys.md) | Several songs in one setlist slot with written transitions, one stage plan, nested Gig Log rows, and the medley reprise exception to once-per-set. |
| [P9-4 Lyrics and URL import](P9-4-lyrics-and-url-import.md) | Personal build only: one search across Ultimate Guitar, Chordie, E-Chords and LRCLIB, URL and saved-page import, a hidden WebKit loader for blocked pages. |
| [P9-5 Mac polish](P9-5-mac-polish.md) | An offline Help Book from the guide, String Catalogs per module (English only), and four extras. |
| [P9-6 iCloud sync](P9-6-icloud-sync.md) | Optional CKSyncEngine sync between the owner's Macs, with library state moved out of the library folder first (S0). |

## Build order and dependencies

1. **P9-6 S0 first.** It moves the index and locks out of the library folder and is independent of everything else, so it starts at once beside any sibling. P9-6 S1 then waits on the owner's portal steps (P9-6 section 21) and its two spikes; S2-S4 follow in order.
2. **Cores in parallel.** P9-1a (page layout, SegueCore only), P9-2a (singer core and stage), P9-3a (medley model, schemas, timing) and P9-5a / P9-5b can run side by side.
3. **P9-3c after P9-2a** (both edit `LayoutRequest`, `SongPreparation` and `StageRequest`); P9-3d after P9-3b and P9-3c. P9-2b and P9-2c follow P9-2a.
4. **P9-1b after P9-1a; P9-1c after P9-1b, P9-2 and P9-3**, because it prints the Lyrics part and medley slots through their models.
5. **P9-4: the bake-off (`docs/research/phase9-import-bakeoff.md`) lands before P9-4's components** are built; P9-4a step a0 fills spec section 4.4 from it. P9-4b may run beside P9-4a once step a2 lands; P9-4c follows both.
6. **P9-5c (String Catalogs) runs last in the wave**, after the sibling UI work has landed, because it sweeps every SegueUI view file.
7. All before the R140 store media pass, which captures the new guide shots.
