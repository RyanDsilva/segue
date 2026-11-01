# P9-1 - PDF export: single chart, songbook, print and the embedded preview

Phase 9 workstream (new, 2026-10-31). Ruling: `docs/release/decisions.md` **R176** (v1.0 builds PDF export before submission: single chart, songbook, print, preview, the Bass chart option and fills); its questions are closed by **R178** (section 18). This spec replaces `docs/phases/4-export.md` (now a pointer here) and carries its resolved decisions forward (`docs/decisions.md` Phase 4: table of contents, no duplex, notes opt-in per export, no branding footer). Built on: **R147** (every section and repeat written out, section map, `RepeatCollapser` gone), **R149** (per-pass show modes: Full, Chords only, First line only, Skip), **R158** P8-2 Q9 (the PDF has its own repeats option, default written out in full) and P8-4 Q7 / Q8 (anyone may use the bass-note view; a "Bass chart" PDF option), **R161** (the Bass chart toggle moved into this build), **R162** Q4 (walk-ups only in the bass-note view), **R167** / **R168** (fills, `t` fills-as-tab, a fill's tab under the line holding its first chord), **R169** (walk-ups into a key change in the new key), **R172** / **R173** (several artists, Movie / Album, slot time from the timeline, "~3:40", unknown time and flagged totals), **R175** (saved fills always show in the bass-note view), **R122** (an out-of-date arrangement plays the full song), **R113** (test budget), **R39** (design directions before new UI), **R140** (one store media pass after these builds), brand.md sections 5, 6 and 9 (light palette for print, shared tokens, same chord/lyric ratio as the stage).

Sibling specs written at the same time: **P9-2 Singer view** (lyrics only) and **P9-3 Medleys**. This spec owns the printing of both and states exactly what it needs from each (sections 8 and 9). Where P9-2 or P9-3 lands a different model, their model wins and only the adapter named there changes; the print rules here stay.

**Build order:** three sessions (section 16). **P9-1a** (pure core: page layout and the print document) may start at once: it adds SegueCore code only. **P9-1b** (drawing, the preview viewer, Bass chart, entry points, analytics) follows P9-1a. **P9-1c** (Lyrics part, medley slots, guide, the one E2E) follows P9-1b **and** the P9-2 and P9-3 cores it calls. All before the R140 store media pass, which captures the guide's PDF shots.

## Session rules (apply to every session)

- `cat` and `ls` are aliased to eza and can hang: use `command cat` / `command ls` or the Read / Grep / Glob tools, and pass this warning to any subagent. Never `rm -rf`: use `trash`. Never an em dash in any file: use "-". Ignore `.build/`.
- Sibling workstreams (P9-2, P9-3, P9-4, P9-5) edit the same working tree concurrently: expect unrelated diffs, never revert or "fix" files you do not own, stage only your own hunks, keep the tree compiling between steps. `StageRequest.swift`, `SetEntryRow.swift`, `FileCommands.swift`, `SetlistBuilderView.swift` and `AnalyticsEvent.swift` are shared seams: edit them hunk by hunk.
- Commits: local only, signed (`git commit -S`), conventional messages, no co-author lines, one commit per resolved step. If signing fails with "failed to fill whole buffer", 1Password is locked: leave the staging intact, tell the orchestrator, never commit unsigned. Never push.
- Test budget (R113): per step only targeted in-process suites (`swift test --filter <Suite>`); tricky pure logic (pagination, keep rules, compact repeats, set list rows, page numbers, file names) gets table-driven in-process tests; PDF output is asserted in-process through PDFKit (section 14). Exactly **one** new XCUITest class for the workstream (section 14.5, in P9-1c). At the end of each session ONE `make quick`, plus ONE `make e2e-one` per existing UI test class the session changed. No `make gate`, no `make check`, no E2E retry loops (a failure is investigated, not re-run), no scratch-worktree builds. Every build or test runs under `lockf -k .build/make.lock`. Write this budget into any subagent's prompt.
- Before using any Apple API not already in the codebase, run the `apple-api-check` skill. This workstream introduces several (section 3.6): check each one.
- Ryan's real library is never opened by a test or a session.
- Stop and ask the orchestrator at any decision fork or spec-vs-code inconsistency, including any case section 18's closed questions do not cover.

## 1. Goal

A band leader prints Friday's set for the drummer and the singer, a bassist takes a bass chart to a rehearsal, and someone emails a chart to a dep. Today Segue cannot put anything on paper: there is no PDF or print code anywhere in the app. After P9-1, any song, setlist slot or whole setlist opens in a PDF preview inside Segue that looks like the stage (the same passes, show modes, pass badges, bass notes, walk-ups and fills, in the light palette), with Save, Share and Print as secondary actions.

**In scope:** a single chart PDF (a library song, or one setlist slot as arranged); a songbook PDF of a setlist (a set list page that is also the table of contents, then every song on its own pages, with PDF outline entries and links), and a songbook of a library multi-selection (R178, section 5.13); the embedded preview viewer with its options and live re-render; Save, Share and Print (`NSPrintOperation` from the PDF); the Bass chart part with walk-ups and saved fills (R161, R175); the PDF repeats option (R158 Q9); several artists and Movie / Album in headers (R172); slot times and set totals on the set list page (R172, R173); the Lyrics part from P9-2 (section 8) and medley slots from P9-3 (section 9); the sandbox print entitlement; analytics; the guide page; one E2E.

**Not in scope:** other file formats (Word, ChordPro bundles); email or cloud integrations beyond the system share sheet; annotations or handwriting; per-member bundles (one export makes one part; export again for another); a separate cover page (R178: the set list page is the contents); tagged/accessible PDF structure (Core Graphics PDF contexts write no tag tree; the preview itself is accessible, section 12); duplex padding (decided: none); a branding footer (decided: none); dark pages (R178: light pages only); a margins control (R178: fixed margins).

## 2. Decisions

1. **One layout engine, two paginations.** The stage's layout core is already split the way `4-export.md` asked for: `LiveLayout` (SegueCore, pure, `TextMeasuring` injected) measures passes (`SongPreparation`), lays sections out (`SectionLayout`), packs them into columns with splitting and keep rules (`ColumnPacker`), and only the last step, `FitSearch`, is stage-specific. Print adds a **page paginator** beside `FitSearch` in `LiveLayout` that reuses everything below it. No `ChartLayout` extraction is needed; the doc's `ChartStyle` is `LayoutStyle` (geometry) + `StageFace` (faces) + the colour tokens.
2. **Print builds its layout request exactly as the stage does.** `StageRequest` (`make`, `renderModel`, `walkUps`, `resolution`) is the one place a stage request is built; print calls the same statics, so arrangements, passes, show modes, pass badges, gig key and capo overrides, bass notes, walk-ups and fills come out identical. The only differences are explicit: no zoom, the print `LayoutStyle`, notes and cues only when the export includes them, diagrams computed when included.
3. **Draw with SwiftUI into a Core Graphics PDF context** (`ImageRenderer.render` per page into one `CGContext(consumer:mediaBox:)`), reusing `StagePlanView`'s drawing of a positioned `LayoutPlan`, `MiniTabView` and the diagram cells under a forced light colour scheme. This keeps one drawing implementation for stage and paper (brand.md 6: "what you edit is what you see on stage"). **Gate:** P9-1a step 0 is a spike proving that this path writes vector, selectable text and vector `Canvas` content (no image XObjects). If it fails, the fallback is a Core Text drawer of the same `PlacedText` runs (`StageFace.ctFont`) plus CG ports of `MiniTabView` and the diagram renderers; stop and ask before switching.
4. **PDFKit for everything after drawing:** the outline, link annotations, document attributes, the preview (`PDFView`), and printing (`PDFDocument.printOperation(for:scalingMode:autoRotate:)`).
5. **Repeats option, default Written out** (R158 Q9). "Compact" prints a pass as a one-line reference only when it is identical, as laid out, to an earlier printed pass of the same part (section 5.6). Never a guess: R147's reasons (notes, extra lines, changed chords) are exactly the cases that stay written out.
6. **Parts:** one "Chart" picker with **Chords** (default), **Bass notes** (the R158 Q8 "Bass chart" option as a picker value, not a separate toggle) and **Lyrics** (P9-2's Singer view, added in P9-1c). One export prints one part.
7. **Stage notes are opt-in per export** (resolved decision 3): sidecar song notes, sidecar cues and the slot's note print only with "Stage notes and cues" on (default off). Chart notes (`{comment}` lines, R145) are part of the chart and always print, as on stage. This makes the guide's existing line "Turn on Show on stage only to keep a note off the printed chart" (`guide/src/content/docs/section-notes.mdx:19`) true.
8. **Print theme:** always the light palette (brand.md 9 "Phase 4"): `ground` paper white, `ink` text, chords `cueText` #C42B30 (5.6:1 on paper, AA; it greys to a readable mid grey on a mono printer), labels `muted`, tints at their stage opacities over white. The viewer's own chrome follows Settings > Appearance; the pages do not.
9. **The set list page is the table of contents** (one page type, not a cover plus a setlist page plus a TOC): every slot with its number, title, credits, key, time and page, breaks as headings with part totals. Because a row's height does not depend on its page number, page numbers need no re-render loop: paginate songs, count the set list pages, offset, done (simplifies `4-export.md` rule 10). There is no separate cover page (R178).
10. **Everything runs in the App Store flavour**; nothing touches `SeguePersonalModules`.

## 3. Current code (verified 2026-10-31)

### 3.1 No export exists

- No file in `App/`, `Packages/` or `UITests/` uses PDFKit, `NSPrintOperation`, `NSPrintInfo`, `PDFView` or a PDF `CGContext`. `ImageRenderer` appears only in tests (`SegueThemeTests/DiagramSnapshotSupport.swift:118-134`, `StageLayoutRenderSupport.swift:71`).
- The only export is the library archive: `AppModel+Export.swift:18-58` (save panel, `-SegueExportPath` test override via `polish.launch.exportPath`, `PolishDependencies.swift:87`, flag `App/Sources/LaunchOptions.swift:96`), shown in File by `FileCommands.swift:28-31`.
- **Sandbox printing is not entitled.** `App/SegueAppStore.entitlements`, `Segue.entitlements` and `Segue-Debug.entitlements` lack `com.apple.security.print`, and `scripts/lib/verify-common.sh:39-51` (`app_entitlements`, the exact allowed set checked by `verify-archive.sh` check 4 and `verify-appstore.sh`) would fail an archive that adds it. Section 10.

### 3.2 The layout core (SegueCore `LiveLayout`, pure)

- `LayoutEngine.plan(_:metrics:)` = `SongPreparation(...).measure()` then `FitSearch(...).plan()` (`LayoutEngine.swift:7-25`).
- `SongPreparation.measure()` (`SongPreparation.swift:14-55`): pins cues, orders passes (`request.passes ?? ArrangementResolver.fullSong`), writes every pass out (`ArrangedSections.build`), runs `BassLine.annotate` for walk-ups and fills when `request.walkUps` is set (`:21-31`), names passes (`PassNaming.names`), applies show modes (Chords only `:108-133`, First line `:135-163`, "+ N more lines"), and turns `request.notes` and unmatched cues into the notes block (`:48-52`). A `.fillTab` item becomes a measured block (`:190-191`).
- `LayoutRequest` (`LayoutRequest.swift:338-387`): `model`, `viewport`, `minLyricSize`, `zoom`, `columns`, `cues`, `notes`, `passes`, `style`, `walkUps`. `LayoutStyle` (`:176-334`, `.stage` at `:334`) holds every size and gap; `TextRole` (`:19-58`) includes `chordDetail`, `approach`, `passBadge`, `modeTag`, `chordSeparator`, `moreLines`. `TextMeasuring` (`:92`), `FixedAdvanceMetrics` (`:145`) for goldens.
- `LaidSections` (`ColumnPacking.swift:23-47`) and `ColumnPacker` (`:49`): `pack(columns:capacity:split:strict:allowWrap:)` (`:97-150`) fills columns greedily; a section that does not fit is **split at once in the remaining room** when `split` is on (it does not first try the next column), preferring a stanza break in the latter half (`splitCount`, `:172-193`); a split part carries the "(cont.)" gutter. `LaidUnit.keepsWithPrevious` keeps a fill's tab with the line above (`SectionLayout.swift:19`, set at `:231`).
- `FitSearch` (`FitSearch.swift`): column candidates limited by `minColumnWidth` (`:101-105`), binary search of the lyric size, `candidate(size:columns:split:allowWrap:)` (`:222`).
- `LayoutPlan` (`LayoutPlan.swift:394-412`): columns of `LayoutBlock`s of `LayoutRow`s of `PlacedText`, plus `passes: [PlanPass]` (`:344-364`: name, mode, tint, weight = length) that the stage map draws. `PlacedFillTab` (`:104-160`) with `metrics(scale:)` and `baseHeight(for:)`.

### 3.3 Building a stage request (SegueUI)

- `StageRequest` (`Live/StageRequest.swift`, being edited by a sibling as this is written): `make(song:slot:prefs:settings:minLyricSize:viewport:bass:)` (`:45-79`) resolves the slot arrangement, joins sidecar notes and the slot note, renders the model and attaches `walkUps(...)`; `walkUps` (`:82-100`) returns a `BassLineContext` only in the bass-note view and only when it draws (walk-ups on, or a fill applies, R175); `renderModel(_:overrides:bass:)` (`:104-117`) applies sidecar display prefs, the bass view **before** the setlist overrides, and forces `showDiagrams = false` (`:110`); `resolution` (`:121-130`). `StageSlot` (`:12-38`) wraps overrides, note and arrangement from a `ShowItem` or a `SetlistEntry`.
- The bass view: `InstrumentProfile.bassView` (`Editing/InstrumentProfile.swift:59-73`) and `DisplayOptions.withBass(_:forcingNotes:)` (`:180-188`), the P8-4 seam for the bass chart. `fillsAsTab` is a user-level setting (`:29`).
- Fills (P8-7 14.5 / 14.6 hooks, verified): `RenderChord.fill: FillRun?` (`Editing/RenderModel.swift:349`; `FillRun` with `inTab`, `RenderModel+Bass.swift:71-94`), `RenderItem.fillTab(FillTabBlock)` with `FillTabBlock.layout(width:metrics:measure:)` (`RenderModel+Bass.swift:146-198`), built by `BassLine.annotate` (`Library/BassLine.swift:112`) from `BassLine.context(for:document:prefs:parts:order:)` (`BassLine+Song.swift:14`). **Through the stage path they need no extra work:** `SongPreparation` annotates when `walkUps` is set, so a print request built by `StageRequest` gets the fills (and walk-up runs, and the tab blocks kept with their line) for free. P8-7 14.5's "the render model already carries" is true after annotation, which this path performs.
- Header data: `RenderHeader` (`RenderModel.swift:152-200`): `artists`, `album`, displayed `key`, `capo`, `tempo`, `scale` (bass view). `SongSummary.credits` ("A, B · Kalank", `Rendering/SongSummary.swift:27-31`), `subtitle` and `performanceLine(_ model:)` (`:73-104`; no capo in Concert or bass view).

### 3.4 Drawing today (SegueUI)

- `StagePlanView` (`Live/StageSongBody.swift:8-35`) draws a `LayoutPlan` exactly as positioned; `StageBlockView` (`:37`) draws tints (`tintColor`, `:79-86`: chorus `ink` 4.5%, bridge `cue` 5%, tab `ink` 3%), gutter labels, pass badges in a hairline box, rows, fill tabs (`MiniTabView`, `:144`) and cue callouts; chord colours by kind (`:236-248`). All colours are `Theme.color` tokens that resolve per colour scheme, so the same view in a light environment draws the light palette.
- `StageFace` (`Live/Layout/StageTypography.swift:18-58`) maps roles to Schibsted Grotesk faces (bundled, OFL, embeddable: `Theme/Fonts/OFL.txt`) and SF Mono for verbatim; `StageTextMetrics` (`:67`) measures with Core Text, glyph fallback included (Devanagari).
- Diagrams are SwiftUI `Canvas` views (`Diagrams/GuitarDiagramView.swift:68-80`, `PianoDiagramView.swift`); `DiagramStripContent` exists because `ImageRenderer` cannot draw a `ScrollView` (`Diagrams/DiagramStrip.swift:34-47`). `MiniTabView` is a `Canvas` too (`Diagrams/MiniTabView.swift:101`).
- The library and editor preview (`Rendering/SongPageView.swift`, `SongSheetView`) is a different, flowing renderer; print follows the stage engine, not it (decision 2).
- Colour token values: `ColorTokenValue.all` (`Theme/ColorTokens.generated.swift:77-97`), generated from `design/tokens.json`.

### 3.5 Setlists and time

- `Setlist` (`Setlists/Setlist.swift:285-304`): `name`, `entries`, `venue`, `date: CalendarDay?`, `targetDuration`, `changeoverSeconds`. `SetlistEntry` (`:157-170`): `kind` (`.song(SongID)` or `.break(SetlistBreak)`, `:151-153`), `overrides`, `note`, `arrangement`. `SetlistOverrides.applied(to:songCapo:)` (`:100-110`). No medley kind yet (P9-3).
- `SlotTimes.slot(_:arrangement:)` (`Library/Timing/SlotTime.swift:59`) and `SlotTime` (`:18-48`: known with `estimated`, or unknown `noTempo` / `noChords`). `SetlistTiming` (`Setlists/SetlistTiming.swift:147-171`; `≥`, `~`, `--:--` at `:300-306`; part totals `PartTiming`) built from a setlist by `SetlistTiming(setlist:songs:defaultChangeover:)` (`SegueUI/Setlists/SetlistEntryDisplay.swift:64`).

### 3.6 Menus, entry points, analytics, guide

- File menu: `FileCommands.swift` replaces `.newItem` and `.saveItem` but not `.printItem`. `MenuShortcuts` (`App/MenuShortcuts.swift:91-165`) has no ⌘P (Play Along is ⇧⌘P, `:127`) and no ⇧⌘E. Menu targets: `AppModel.menuSong(focused:)` and `shownSetlist` (`App/Commands/SegueCommands.swift:41, 53`).
- Setlist builder: the toolbar "Setlist" menu (`Setlists/SetlistBuilderView.swift:236-251`) renders `SetlistActions` (`:269-300`: Rename, Details, Duplicate, Show in Finder, Move to Trash); slot rows have a context menu (`Setlists/SetEntryRow.swift:92`).
- Analytics: `featureUsed(FeatureKey, ...)` (`Services/AnalyticsEvent.swift:46`), `FeatureKey` (`Services/FeatureKey.swift`; P8-4 6.6's `bassChart` was never added), `ErrorCode` (`AnalyticsEvent.swift:262-280`), summary events with closed enums and `SmallBucket` (pattern: `AnalyticsEvent+Timing.swift`); catalogue `docs/release/specs/WS3-services.md` rows 1-30 (row 30 is P8-8's).
- Guide: sidebar `guide/astro.config.mjs:10-58` (no print page); links `App/SegueLinks.swift:51-65` (`Guide` enum, site-checked).
- APIs new to the codebase (run `apple-api-check` on each): `ImageRenderer.render(rasterizationScale:renderer:)` outside tests, `CGContext(consumer:mediaBox:_:)` + `beginPDFPage` / `endPDFPage` / `closePDF`, `PDFDocument`, `PDFOutline`, `PDFDestination`, `PDFAnnotation` (`.link`), `PDFDocumentAttribute`, `PDFView` (in an `NSViewRepresentable`), `PDFDocument.printOperation(for:scalingMode:autoRotate:)`, `NSPrintInfo`, `ShareLink` with a file URL, `CommandGroup(replacing: .printItem)`.

## 4. What gets exported, from where

| Target | Entry points | Content |
|---|---|---|
| **Song** | File > Export PDF... / Print... with a song focused or shown (library list, detail pane, editor); song row context menu "Export PDF..." | The full song as written (like R150's single-song sessions), its sidecar display prefs (transpose, Shapes/Concert, Nashville, diagrams), the user's bass view when the part is Bass notes. |
| **Slot** | Slot row context menu "Export Slot as PDF..." | That slot as the stage plays it: its arrangement's passes and modes (R122, R149), its gig key and capo overrides, its note (with stage notes on). An out-of-date arrangement prints the full song with a muted line under the header: "Arrangement out of date: printed as written". |
| **Setlist** | File > Export PDF... / Print... with a setlist shown and no song focused; builder toolbar "Setlist" menu "Export PDF..." and "Print..." | The songbook: set list page(s), then every song slot as a slot export, in set order; medley slots per section 9. Breaks print on the set list page only. |
| **Selection** | File > Export PDF... / Print... with two or more library songs selected; the library multi-selection context menu "Export N Songs as PDF..." (R178) | A songbook of the selected songs (section 5.13): a contents page, then each song as a song export, in the library list's current order. |

- File > **Export PDF...** (⇧⌘E) and File > **Print...** (⌘P) both open the same preview (section 6); Print... opens it with the Print button focused, and ⌘P inside the preview prints. R178 confirms this pairing. `CommandGroup(replacing: .printItem)` holds both, so no system Page Setup / Print item survives. Both are disabled when no library is open, when nothing exportable is targeted, and while a show is running or starting (`isPerforming || isStartingShow`, like the archive export): the stage owns the keyboard.
- An empty setlist (no song slots) disables the setlist entries with help "Add a song to export this setlist". A song with no sections exports one page with its header and "No lyrics yet." (as `SongPageView` does).

## 5. The pages

### 5.1 Page geometry

- **Paper:** A4 (595 x 842 pt) or US Letter (612 x 792 pt), portrait. Default from the locale (`Locale.current.measurementSystem == .us` -> Letter, else A4), remembered once changed.
- **Margins:** fixed, 40 pt top, 36 pt sides and bottom (R178: no margins control, which drops `4-export.md`'s "configurable").
- **Text size:** Small 10 pt, Medium 11.5 pt (default), Large 13 pt lyric size; chords 0.82 x lyric, bold, `cueText` (brand.md 6). This is a fixed size, not auto-fit, except under "Fit on one page" (5.9).
- **Columns:** Auto (default), 1, 2. Auto picks 2 when every lyric line of the song fits a column without wrapping at the chosen size, else 1 (the stage's no-wrap preference, decisions.md "Auto-fit wrapping (revised)"). One song keeps one column count across its pages.
- **`LayoutStyle.print(lyricSize:)`** (new, `LayoutRequest.swift`, one place, starting values tuned in P9-1b against the design mockups): `gutterWidth` 44, `maxGutterWidth` 72, `gutterGap` 10, `columnGap` 24, `minColumnWidth` 210, `maxColumns` 2, `maxLyricSize` = the chosen size, `labelSize` 8.5, `minLabelSize` 8, `labelDetailSize` 7.5, `passBadgeSize` 7.5, `modeTagSize` 6.5, `cueSize` 9, `noteSize` 9.5, `comfortableLyricSize` = the chosen size; ratios (`lineHeight` 1.25, `chordRatio` 0.82, `sectionSpacing`, `blockInset`) as `.stage`.

### 5.2 Song page anatomy

- **First page header** (top margin, left aligned, full width): title 20 pt ExtraBold `ink` (tracking as `Theme.tracking.title`); credits line `SongSummary.credits` ("Vishal Dadlani, Shekhar Ravjiani · Kalank", 10 pt Medium `muted`, R172; Movie / Album shows here though not on stage, R178); performance line `SongSummary.performanceLine(model)` ("G, capo 2, 96", 10 pt SemiBold `muted`; in the bass part the sounding key and no capo); in the bass part the scale line `RenderHeader.scale` ("Sounding A major: A B C# D E F# G#", 9 pt Medium `muted`); the section map line (5.5); in a setlist songbook, right aligned on the title's baseline, "4 of 18" (the slot number, 10 pt SemiBold `muted`; "Medley 5 · 2 of 3" for a medley member, section 9; a selection songbook has no slot number). A 0.5 pt `line` rule under the header.
- **Continuation pages:** a one-line header "Harbour Lights (cont.)" (10 pt Bold `ink`) with the slot number on the right; then the body. A section split across a page keeps its "(cont.)" gutter label (the packer's existing continuation gutter).
- **Footer** (every page, 8.5 pt Medium `muted`, baseline 20 pt above the paper edge): left, in a songbook, "Friday Set" (the setlist name); right "Page 7 of 31" (songbook: the document page; single chart: the song's pages). Nothing else: no branding (resolved decision 4), no date.
- **Body:** the `LayoutPlan`s of section 5.3, drawn by `StagePlanView` in the light scheme: gutter labels (chorus `ink`, others `muted`), the "2 of 3" pass badge, the "CHORDS" / "1ST LINE" mode tag, Chords only rows with `|` separators, "+ N more lines (first line only)", tints, `{comment}` lines, tab and grid lines in SF Mono, cues in their callouts (when included), fill tabs.

### 5.3 Pagination (new `LiveLayout/PageLayout.swift`, pure)

`PageLayout.paginate(_ request: LayoutRequest, page: PageGeometry, metrics: any TextMeasuring) -> [LayoutPlan]`, where `PageGeometry { firstBody: LayoutSize, laterBody: LayoutSize, columns: Int }` (the first page's body is shorter by the header). It runs `SongPreparation(...).measure()`, lays out with `SectionLayout` at the fixed size, then packs with a print policy on `ColumnPacker`. Each returned plan is one page, its columns in reading order (down the first column, then the second), `fit = .fits`, `pageStops = []`, `passes` the passes whose blocks start on that page.

Rules (each one a table-driven test, section 14.1):

1. The smallest unit is a laid unit: a chord+lyric line pair, a comment, a tab line, a Chords only row, a fill tab (kept with the line above it, `keepsWithPrevious`). A unit is never split.
2. **Whole first:** a section that does not fit the remaining room but fits an empty column moves whole to the next column (or page). Only a section taller than an empty column splits, between units, preferring a stanza break in the latter half (the existing `splitCount`). This is a new `ColumnPacker` policy flag (`moveWholeFirst: Bool`, default false so the stage is byte-for-byte unchanged).
3. **No orphan heading:** a split leaves at least two lyric units with the section's head (label, cues) and carries at least two to the next part; otherwise the whole section moves (new `minimumUnitsAtSplit`, default 1 for the stage).
4. A tab or grid line wider than the column wraps as on stage (`brokeVerbatim`); print never fails a pack for it.
5. Notes (stage notes, when included) form the first block, as on stage.
6. The diagram block (5.8) and the transition callout (section 9) are placed after the last section by the same rules, never split.
7. Each song (and each medley slot) starts on a new page; the members inside a medley flow on without page breaks (R178, section 9). No blank padding pages (resolved decision 2).

### 5.4 Show modes and passes

Printed exactly as the stage lays them out (R149): Full passes in full; Chords only passes as chord rows with `|` separators and the "CHORDS" tag; First line passes as the first line plus "+ N more lines (first line only)" and the "1ST LINE" tag; Skip passes absent. Every repeat is written out (R147) unless the repeats option is Compact (5.6). The gutter's "2 of 3" badge marks repeated passes, as on stage.

### 5.5 Section map line

The stage map strip (R147) becomes one muted text line under the header (9 pt Medium `muted`, wrapping to at most two lines, then "..."), built from the first page's `LayoutPlan.passes` across all pages in played order: each pass's `PassName.short` plus its number when repeated, with the mode as a suffix: "Intro · V1 · Ch · V2 · Ch 2/3 · Br (chords) · Ch 3/3 (1st line) · Outro". Shown when the song has more than one shown pass; option "Section map" (default on). Accessible text in the PDF is the same string. The one-line text roadmap replaces the stage's chip map on paper (R178).

### 5.6 Repeats option

- **Written out** (default, R158 Q9): every pass laid out in full.
- **Compact:** a Full pass prints as one reference row when it is identical, as measured, to an earlier printed Full pass of the same part in this song: same `source` part, same items after `BassLine.annotate` (so a different walk-up into what follows, a fill that plays only on one pass, a cue, or a changed chord keeps it written out), same show mode. The reference row is `TextRole.moreLines` style: "Chorus 2 of 3: as Chorus 1 above" (or "as Chorus 1 on page 2"), with the pass badge in the gutter. Chords only and First line passes are already short and never compacted. Implemented in `PageLayout` before packing (`CompactRepeats.apply(_ sections: [MeasuredSection]) -> [MeasuredSection]`, pure); the stage never uses it.

### 5.7 Bass notes part (R158 P8-4 Q8, P8-4 section 7.4, moved here by R161)

- **What it prints:** every song rendered with `DisplayOptions.withBass(profile, forcingNotes: true)`, i.e. `StageRequest.renderModel(..., bass: profile.withNotesForced.bassView)`: bass notes at sounding pitch; the small full chord beside when `chordBeside` is on (`TextRole.chordDetail`); Nashville "5 · D" when the song's Nashville toggle is on; slot key and capo overrides applied; header key the sounding key with no capo; the scale line.
- **Walk-ups:** printed as on stage (the user's density setting, the pick else the top candidate, R161; R169 into key changes): dark grey runs (`TextRole.approach`, `muted` on paper, mono-safe), never buttons.
- **Fills (R175, P8-7 14.5):** saved fills print whenever the part is Bass notes, whatever the walk-up density: as note-name runs over their chords (`ink` 70%), or as the mini tab under the line holding the fill's first chord when the fill's `show` is tab or "Fills as tab" is on; a run whose `inTab` is set is not drawn (its block is). Option **Fills as tab** appears in the Bass part only when any exported song has a fill; default = `profile.fillsAsTab` (the stage's `t` setting); changing it in the preview never changes the user's setting.
- **Diagrams:** none; the Chord diagrams option is disabled with help "Bass charts print no chord diagrams".
- **Default part:** Bass notes when the user's bass-note view is on (`profile.bassNotes`), else Chords (P8-4 7.4: the export matches what the performer sees). Available to anyone (R158 Q7).
- **Naming:** file name gains " (Bass)" ("Harbour Lights (Bass).pdf", "Friday Set (Bass).pdf"); PDF keywords gain "bass chart".

### 5.8 Chord diagrams

- Option **Chord diagrams** (Chords part only): default = each song's own diagram toggle (sidecar `showDiagrams`); turning it on prints diagrams for every song, off for none (a three-state pop-up "As each song / All songs / None" in a songbook, a checkbox for one song).
- Built from `RenderModel.diagrams` rendered with `showDiagrams` on (a `diagrams:` parameter on `StageRequest.renderModel`, default false, so the stage is unchanged), drawn with `DiagramStripContent` cells at `.compact` size, wrapped into rows across the body width, as one block **after the last section** (R178), never split; it moves to a new page if it does not fit.
- The instrument and tuning are the song's (guitar, piano, `{meta: tuning}`), as in the preview.

### 5.9 Fit on one page (single chart only)

Option **Fit on one page** (default off; disabled for a songbook). When on: `LayoutEngine.plan` with `viewport` = the first page body, `style = .print(lyricSize: chosen)`, `minLyricSize` 9, `columns` from the option (Auto = nil, which tries 1 and 2), `zoom` 1. If the plan's `fit == .fits`, the song prints on one page at the fitted size; otherwise it falls back to normal pagination at the chosen size and the option's caption reads "Doesn't fit at 9 pt: printing 2 pages". This reuses `FitSearch` unchanged.

### 5.10 The set list page (songbook only; decision 9)

- **Head:** setlist name 24 pt ExtraBold `ink`; a muted line "The Anchor · Fri 23 Oct 2026 · 18 songs · 1:12:30" (venue, `CalendarDay.displayText`, song count, the whole total `SetlistTiming.totalText`: "≥1:12:30 + 2 unknown" when any slot is unknown, "~1:12:30" when estimated, R172 / R173). A 0.5 pt rule.
- **Rows** (one per slot, 10.5 pt; a row is two lines when it has credits): number (SemiBold `muted`, right aligned), title (SemiBold `ink`) with credits under it (9 pt Medium `muted`, `SongSummary.credits`), key as printed for that slot (`performanceLine` without the tempo: "A, capo 2", or the sounding key in the bass part), time (`ItemTiming.timeText`: "3:40", "~3:40", "--:--"), page (the slot's first page). The whole row is a PDF link to that page.
- **Breaks** (R85): a heading row "Set 2" (11 pt Bold `ink`) with its part total on the right ("45:10", "≥45:10 + 1 unknown"); the intermission length when set ("Interval 20:00", muted). Part totals follow `SetlistTiming.parts`.
- **Missing song** (slot whose song is not in the library): the row reads "Song not in library" in `muted`, no time, no page, and no song pages follow for it.
- **Medley slots:** section 9.
- More rows than a page holds continue on a second set list page with the head reduced to "Friday Set (cont.)". Rows never split.
- **Page numbers:** after every song is paginated, `setListPages` is known from the row count alone; song pages are numbered from `setListPages + 1`.

### 5.11 Document metadata, outline, links, file names

- **Attributes** (`PDFDocumentAttribute`): Title = song title, setlist name, or "Songbook" for a selection; Author = the song's artists joined ("A, B") for a single chart, none for a songbook; Subject = "Venue · date" for a songbook; Creator "Segue"; Keywords = the song's tags (single chart) or "songbook", plus "bass chart" / "lyrics" for those parts. Creation and modification dates from the injected clock (tests fix them).
- **Outline:** single chart: none (one entry, the title). Songbook: "Set list", then one entry per slot "3. Harbour Lights", nested under its break heading ("Set 2") when the set has breaks, medley members nested under the medley (section 9).
- **Links:** every set list row links to its slot's first page (`PDFAnnotation` `.link` with a `PDFDestination` at the page top); a medley member row links to its inline header's point (section 9).
- **File names** (`PrintFileName`, pure): "<title>.pdf" / "<setlist name>.pdf" / "Songbook (N songs).pdf" for a selection, suffix " (Bass)" or " (Lyrics)" by part, characters illegal in file names (`/`, `:`) replaced by "-", trimmed to 120 characters; an untitled song is "Untitled.pdf".

### 5.12 Light and dark

Pages are always light (decision 8): the renderer forces `\.colorScheme = .light` on every page view, so `Theme.color` resolves the light tokens whatever Settings > Appearance says. The preview sheet's chrome (options column, buttons, the gray around the pages) follows the app appearance; `PDFView`'s background uses `surfaceAlt`. There is no dark-page variant (R178: light pages only).

### 5.13 A songbook from a library multi-selection (R178)

- **Entry:** with two or more songs selected in the library list, File > Export PDF... / Print... target the selection (a single selected song stays a Song export), and the selection's context menu gains "Export N Songs as PDF...". Disabled while a show runs, as in section 4.
- **Order:** the library list's current sort and filter order, as the user sees it; no reordering in the preview (make a setlist for a running order).
- **Contents page:** the 5.10 set list page with the head "Songbook" (24 pt ExtraBold) and a muted line "12 songs" (no venue, date or total: a selection is not a set, so no times or totals print); rows numbered 1..N with title, credits, key as written and page, each a link. No breaks, no medley rows.
- **Songs:** each as a Song export (section 4: the full song as written with its sidecar display prefs), each starting a new page; the header carries no slot number; the footer's left side reads "Songbook".
- **Outline:** "Contents", then one entry per song. **Analytics:** `segue.target` = `selection`.

## 6. The preview viewer

### 6.1 Design step (R39)

Step 0 of P9-1b: two or three mockups of the preview sheet (options as a left column vs a top bar; placement of Save / Share / Print) in the app's style (Apple-native, dark-first chrome, light pages), shown to Ryan before building. The behaviour below holds for every direction.

### 6.2 Sheet

- A sheet on the main window (`PDFPreviewSheet`, SegueUI `Export/`), sized to the window (minimum 900 x 640, as the fill sheet sizes itself), identifier `segue.pdf.sheet`.
- **Title row:** "Harbour Lights" / "Friday Set" (18 pt Bold), subtitle "Song PDF · 2 pages" / "Slot PDF · Friday Set, slot 4 · 2 pages" / "Songbook PDF · 18 songs · 31 pages".
- **Pages:** a `PDFView` (`NSViewRepresentable`, `displayMode = .singlePageContinuous`, `autoScales = true`, page shadows on), identifier `segue.pdf.view`; a page indicator "Page 3 of 31" under it. Pages are vector, so zoom (pinch, ⌘+ / ⌘-) stays sharp.
- **Options** (one column, `Form` grouped style, identifiers `segue.pdf.option.<name>`), each re-rendering the preview on change:

| Option | Values | Default | Shown for | Remembered |
|---|---|---|---|---|
| Chart (`part`) | Chords / Bass notes / Lyrics | Bass notes if `profile.bassNotes`, else Chords | all; Lyrics only after P9-1c | no (follows the user's view each time) |
| Paper (`paper`) | A4 / US Letter | locale | all | yes |
| Text size (`size`) | Small / Medium / Large | Medium | all | yes |
| Columns (`columns`) | Auto / 1 / 2 | Auto | all | yes |
| Fit on one page (`fitOnePage`) | on / off | off | song, slot | yes |
| Repeats (`repeats`) | Written out / Compact | Written out | all | yes |
| Section map (`sectionMap`) | on / off | on | all | yes |
| Chord diagrams (`diagrams`) | As each song / All songs / None (checkbox for one song) | As each song | Chords part | yes |
| Fills as tab (`fillsAsTab`) | on / off | `profile.fillsAsTab` | Bass part, when a song has a fill | no |
| Stage notes and cues (`stageNotes`) | on / off | off | all | no (privacy: off every time, resolved decision 3) |

  Remembered values live in `UserDefaults` under `export.pdf.options` (lenient decode, reset by Settings > Data > Reset All Settings, whose list and message gain "Export"). Disabled options keep their row with help text naming why ("Bass charts print no chord diagrams", "Songbooks always paginate").
- **Actions** (bottom bar, all `.segueSecondary` except Done, which is the default `.seguePrimary` button and closes the sheet; Esc closes too): **Share** (`ShareLink` with the rendered PDF written to a temporary file named by 5.11, identifier `segue.pdf.share`), **Save PDF...** (⌘S inside the sheet: `NSSavePanel` with the 5.11 name and `.pdf` only, or `-SegueExportPath` in tests; on success flash "Saved Harbour Lights.pdf" in the sheet; identifier `segue.pdf.save`), **Print...** (⌘P inside the sheet, identifier `segue.pdf.print`): `PDFDocument.printOperation(for:scalingMode: .pageScaleNone, autoRotate: false)` with an `NSPrintInfo` whose paper size matches the chosen paper and whose margins are zero (the pages carry their own), shown as a sheet on the preview window. The system print panel's own "PDF" menu stays available.
- **Rendering state:** the first render shows a centred `ProgressView` "Making the PDF..."; a re-render keeps the previous pages visible with a small spinner and "Updating..." beside the page indicator; actions are disabled until the current options' PDF is ready, so a saved or printed file always matches the options shown. An option change cancels the render in flight.
- **Errors:** a render or save failure shows an inline banner in the sheet, "Segue could not make this PDF (reason). Try again", with a Try Again button; nothing is written to the destination on failure; `errorOccurred(.pdfExport)` is recorded.
- **Live changes:** if a song in the export is edited while the sheet is open, the sheet does not follow it (the PDF is a snapshot of the songs when opened); closing and reopening picks up edits.

### 6.3 Keyboard

⌘P print, ⌘S save, Esc / Return done, ⌘+ / ⌘- zoom the pages, Page Up / Page Down scroll a page. The new menu shortcuts (File > Export PDF... ⇧⌘E, File > Print... ⌘P) go into `MenuShortcuts.all`, the clash test, and `guide/src/data/keyboard.json` (`make guide-keys`).

## 7. Data and render pipeline

### 7.1 Modules and types

- **SegueCore `LiveLayout`** (pure): `LayoutStyle.print(lyricSize:)`; `PageGeometry`; `PageLayout.paginate`; `CompactRepeats`; the `ColumnPacker` policy flags `moveWholeFirst` and `minimumUnitsAtSplit` (defaults keep the stage unchanged).
- **SegueCore `Printing`** (new target; deps `Editing`, `Library`, `LiveLayout`, `Setlists`; pure, no AppKit): `PrintOptions` (the 6.2 values, `Codable`), `PrintPart` (`chords`, `bass`, `lyrics`), `PrintDocument { pages: [PrintPage], outline: [PrintOutlineEntry], metadata: PrintMetadata, fileName: String }`, `PrintPage` (`.setList(SetListPage)` / `.song(SongPage)`), `SongPage { header: PrintHeader, plan: LayoutPlan, isFirst: Bool, slotLabel: String?, footer: PrintFooter, extras: [PrintBlock] }` (`PrintBlock`: diagrams, transition, out-of-date note), `SetListPage { head: SetListHead, rows: [SetListRow] }`, `SetListRow` (`.song`, `.breakHeading`, `.missing`, `.medley`), `PrintFileName`, and `PrintAssembler.document(songs:setList:options:geometry:metrics:) -> PrintDocument`, which numbers pages, builds rows, outline and links. Inputs are prepared requests, so `Printing` never touches `SegueUI`.
- **SegueUI `Export/`** (new folder): `PrintRequests` (builds one `LayoutRequest` per slot through `StageRequest`, plus diagrams and headers, decision 2), `PrintPageView` (SwiftUI, one page: header, `StagePlanView`, extras, footer, under `.environment(\.colorScheme, .light)`), `PDFRenderer` (`@MainActor`: `ImageRenderer.render` of each `PrintPageView` into one PDF `CGContext`, then `PDFDocument` outline, links and attributes), `PDFPreviewModel` (`@MainActor @Observable`: target, options, state, the current `PDFDocument`, cancellation, analytics), `PDFPreviewSheet`, `PDFKitView` (`NSViewRepresentable`), `AppModel+PDF.swift` (open, save panel, print operation).

### 7.2 Steps of one render

1. **Snapshot** (main actor, fast): the target's `SongRecord`s and setlist entries, the instrument profile, user shapes, the options, the clock.
2. **Requests** (main actor, cheap): `PrintRequests` builds per slot `(LayoutRequest, header, diagrams, slot label)` through `StageRequest.make`-equivalent statics with `style = .print(...)`, `zoom` 1, `notes` / `cues` empty unless `stageNotes`, `bass` per part.
3. **Layout** (off main, `Task.detached`, one child task per song in a `TaskGroup`; everything is `Sendable`): `PageLayout.paginate` (or `LayoutEngine.plan` for Fit on one page) with `StageTextMetrics`, then `PrintAssembler.document`.
4. **Draw** (main actor, `ImageRenderer` is main-actor bound): each `PrintPage` -> `PrintPageView` -> `ImageRenderer.render` into the PDF context; `Task.checkCancellation()` and `await Task.yield()` between pages so the sheet stays responsive.
5. **Finish:** `PDFDocument(data:)`, outline, link annotations, attributes; publish to the model.

### 7.3 Cost and caching

- Target (acceptance): a 20-song songbook re-renders in under 1 s on Apple Silicon and under 3 s on the 8 GB low-spec target Mac (the owner's low-power rule), measured by a timing-budget test (14.4).
- If drawing misses the budget: cache drawn pages per song keyed by (song source hash, sidecar hash, slot, the options that affect layout, paper), so toggling an option that changes one song (e.g. none) or only the set list page reuses the rest. Build the cache only if the measurement needs it; record the measurement in the step commit.

## 8. Interface for P9-2: print singer view

P9-1 prints the Singer view as the **Lyrics** part. What print needs from P9-2 (P9-2 owns the rules; print follows them):

1. **One transform at the layout-request level** that the stage honours, e.g. `LayoutRequest.lyricsOnly: Bool` or a `DisplayOptions` / `RenderModel` mode, so that `SongPreparation` produces no chord rows, no chord runs, no walk-up or fill runs and no fill tabs. Print sets it through the same `StageRequest` path as the stage's Singer view; it never strips chords itself.
2. **P9-2 decides** what Chords only passes, First line passes, tab/grid sections and `{comment}` lines do in the Singer view, and whether the header shows key and capo. Print prints exactly that.
3. **Print adds:** the Chart picker value "Lyrics"; Chord diagrams, Fills as tab and the scale line are disabled or absent; the default text size for Lyrics is Large (13 pt); file name suffix " (Lyrics)"; keywords "lyrics"; the set list page's key column reads the key as the Singer view's header shows it (or is omitted if P9-2 hides keys).
4. **Test hook:** P9-2's in-process fixture song (with chords) must also be usable by `PrintLyricsTests` (14.2): extracted text contains every lyric word and no chord symbol.
5. Until P9-2 lands, the Lyrics value is absent (not disabled): P9-1c adds it.

## 9. Interface for P9-3: medley slots

What print needs from P9-3's model (names are print's assumption; P9-3's names win):

1. A setlist entry kind for a medley: an optional title, an ordered list of member songs, each member with its own overrides, arrangement and note (the `StageSlot` fields), and the written transition between consecutive members.
2. `SetlistTiming` (P9-3 extends it) gives the medley's total and each member's time, with the same unknown and estimated rules.
3. **How a medley slot prints in a songbook:**
   - **Set list page:** one numbered row "5  Medley: Tujh Mein Rab / Kesariya / Tum Hi Ho" (or the medley's title) with the medley's total and the first member's page; under it, one indented row per member, numbered "5a", "5b", "5c" (R178), with its credits, key, time and page, each a link to the member's inline header (a `PDFDestination` at the header's point, not the page top, since members share pages).
   - **Outline:** "5. Medley" with one child per member ("5a. Tujh Mein Rab"), each pointing at its inline header.
   - **Body (R178: members flow on without page breaks):** the medley slot starts on a new page; the first member prints its full first page header with "Medley 5 · 1 of 3" on the right. Each later member follows straight on in the same column flow, with no page break: after the previous member's last section comes the transition block (kept whole, 10 pt Medium `ink` in a hairline box): "Into Kesariya: <transition text>" (or "Into Kesariya" when no text is written), then the member's own inline header (title 14 pt Bold `ink`, credits and performance line as 5.2, its section map line, "Medley 5 · 2 of 3" on the right), kept with at least its member's first two units (a header never ends a column). Each member prints as a slot export (its arrangement, key, capo, stage notes when included). A continuation page's one-line header names the member at the top of that page ("Kesariya (cont.) · Medley 5 · 2 of 3"). Pagination: `PageLayout.paginate` takes the members' measured sections as one sequence with the transition and member-header blocks between them (a new `PageLayout.paginateMedley`, or a `[MemberRequest]` overload), so every 5.3 rule holds across the joins.
   - **Single slot export of a medley slot:** the members in order with their transitions, as above, without the set list page.
4. Until P9-3 lands, songbooks have no medley rows; P9-1c adds the adapter (`PrintRequests` and `SetListRow.medley`).

## 10. Sandbox and App Store

- Add `com.apple.security.print` = true to `App/Segue.entitlements`, `App/Segue-Debug.entitlements` and `App/SegueAppStore.entitlements`, set `"ENABLE_RESOURCE_ACCESS_PRINTING": "YES"` beside `ENABLE_OUTGOING_NETWORK_CONNECTIONS` on both app targets in `Project.swift` (`:181-184`, `:322`; WS1's rule that the sandbox build settings and the entitlements files agree; check the setting name with `apple-api-check`), and to `app_entitlements` in `scripts/lib/verify-common.sh:39-51`, so `verify-archive.sh` check 4 and `verify-appstore.sh` accept the new set; note the change in `docs/release/specs/WS1-release-pipeline.md` where the allowed set is listed and in `docs/release/app-store-connect.md` review notes if entitlements are explained there.
- Save goes through `NSSavePanel` (the existing user-selected read-write entitlement); Share writes to the app's temporary directory only.
- Fonts: Schibsted Grotesk is OFL and embeds as a subset; SF Mono and fallback system faces embed as the system allows.

## 11. Analytics (non-PII, closed vocabulary, WS3)

- **Row 31** (or the next free row at build time: P9-2 and P9-3 may claim rows concurrently), `Segue.Export.pdf`, one per preview sheet closed, `AnalyticsEvent.pdfExported(PDFExportSummary)` in `Services/AnalyticsEvent+Export.swift`:
  - `segue.target` (`song`, `slot`, `setlist`, `selection`), `segue.part` (`chords`, `bass`, `lyrics`), `segue.paper` (`a4`, `letter`), `segue.size` (`small`, `medium`, `large`), `segue.columns` (`auto`, `one`, `two`), `segue.repeats` (`full`, `compact`), `segue.fitOnePage`, `segue.sectionMap`, `segue.stageNotes` (Bool each), `segue.diagrams` (`asSong`, `all`, `none`, `notApplicable`), `segue.fills` (`none`, `names`, `tab`: what the PDF drew), `segue.saved`, `segue.printed`, `segue.shared` (Bool each: the sheet's outcomes), `segue.songs`, `segue.pages`, `segue.medleys`, `segue.optionChanges` (SmallBucket each), `segue.renderTime` (new `RenderTimeBucket`: `under250ms`, `under500ms`, `under1s`, `under2s`, `over2s`; the first render of the session, to watch the low-spec budget).
  - No titles, names, venues, file names or paths.
- `ErrorCode.pdfExport` (render or save failure).
- `FeatureKey` gains nothing: the summary's `part` replaces P8-4 6.6's planned `bassChart` key (one signal, not two); `docs/phases/8-workstreams/P8-4-bass.md` 6.6 is noted as superseded in the P9-1b commit message, not edited by this spec.
- Update `ServicesVocabularyTests`, the WS3 catalogue row, and `AnalyticsContextEnvironment` if a context note is needed.
- Proposed extra signals (section 18 Q12, still open): the share sheet's chosen service type is not available to the app, so none; a `helpOpened(.pdf)` when the sheet's help button opens the guide.

## 12. Accessibility

- Every option is a labelled native control with its identifier; disabled rows carry help text; the page indicator is a live accessibility value.
- `PDFView` exposes page text to VoiceOver; the sheet's title row is a header.
- Paper output: colour never carries meaning alone (labels name sections; the pass badge has a box and text; Chords only rows also have the "CHORDS" tag); every text colour passes AA on paper (brand.md 5: `ink` 18.9:1, `cueText` 5.6:1, `muted` 7.4:1); the smallest printed text is 6.5 pt bold uppercase (mode tag), every reading role 8.5 pt or more.

## 13. Guide pages and links

- New page `guide/src/content/docs/print-and-pdf.mdx` ("Print and PDF"), in the "Build the set" group after "Arrange sections" (`astro.config.mjs`). Headings with stable ids: `#song` (export one song or slot), `#songbook` (the set list page, page links, breaks, medleys), `#options` (each option in one line), `#bass` (the Bass notes part, walk-ups, fills, tab), `#lyrics` (the Lyrics part, linking P9-2's page), `#print` (Print, Save, Share). Screenshots (light and dark chrome, light pages) are captured in the R140 store media pass: add shot ids `pdf-preview` and `pdf-songbook` to `guide/src/data/shots.json` with placeholders until then.
- Edits: `play-bass.mdx` gains a "Print a bass chart" paragraph linking `print-and-pdf#bass`; `build-a-set.mdx` links `print-and-pdf#songbook`; `section-notes.mdx:19` links `print-and-pdf#options` (the stage notes option); `keyboard.mdx` picks up ⇧⌘E and ⌘P through `make guide-keys`.
- `SegueLinks.Guide` gains `.pdf` (`/guide/print-and-pdf`) for the sheet's help button; the site check verifies it.

## 14. Tests (R113 budget)

### 14.1 SegueCore, pure (Swift Testing, table-driven, `FixedAdvanceMetrics` unless noted)

- `PageLayoutTests`: a short song fits one page; a long song breaks between sections; "whole first" moves a section that fits an empty page; an over-long section splits at a stanza break with "(cont.)"; no orphan heading (fewer than 2 units never left or carried); a fill tab never separated from its line; first page body shorter than later pages; 2 columns read down then across; Auto columns picks 1 when a line would wrap; the stage packing is unchanged with the default policy (the existing `LiveLayoutEngineTests` and corpus stay green).
- `CompactRepeatsTests`: identical chorus passes compact with the right reference text and page; a pass with a different walk-up, a fill on one pass only, a cue, or a Chords only mode stays written out; Written out leaves everything.
- `PrintAssemblerTests`: page numbering with 1 and 2 set list pages; set list rows for songs, breaks with part totals, an unknown slot ("--:--", total "≥... + 1 unknown"), an estimated slot ("~3:40"), a missing song; outline nesting under breaks; links target first pages; metadata per part; slot labels.
- `PrintFileNameTests`: suffixes, illegal characters, length, untitled, a selection songbook.
- `PrintSelectionTests` (in `PrintAssemblerTests`): a 3-song selection makes a "Songbook" contents page in the given order with no times, totals or slot numbers, links to each song's first page, and the selection outline.
- `PrintRequestParityTests` (SegueUI target, in-process): for a slot with an arrangement, Chords only and First line passes, a gig key override and a fill, the print request's measured sections equal the stage request's (same passes, modes, badges, chord texts, fill runs and tabs); only style, zoom and notes differ.

### 14.2 SegueUI, in-process PDF assertions (`SegueThemeTests`, real Core Text, real PDFKit)

- `PDFSpikeTests` (P9-1a step 0, kept as a guard): a page with a lyric line, a chord, a guitar diagram and a fill tab renders through `ImageRenderer` into a PDF whose `PDFPage.string` contains the lyric and chord, and whose page resources contain no image XObject (vector only).
- `PDFExportTests`: export fixture songs (short, long, chords only, tab, transposed, Nashville, Devanagari lyrics, with diagrams) as single charts; assert via PDFKit: page count, page size per paper, header text (title, "A, B · Kalank", "G, capo 2, 96"), footer "Page 1 of 2", chords in transposed / Nashville form, no line pair split (each lyric line's chord and lyric fall on the same page), "(cont.)" on a split section, diagrams present / absent per option, stage notes absent by default and present with the option, `{comment}` always present.
- `PDFSongbookTests`: a 3-song setlist with a break and an arranged slot: set list page text and order, slot times and totals, link annotations pointing at the right pages, outline titles and nesting, each song starting a new page, the arranged slot printing its passes ("2 of 3", "CHORDS"), an out-of-date arrangement printing in full with its note.
- `PDFBassChartTests` (P8-4 11.5, moved here): the P8-4 11.4 song (`{key: G}`, `{capo: 2}`, `[G]Hello [G/B]there [C]friend`) with the Bass notes part: text contains "A", "C#", "D", not "G/B"; header sounding key without capo and the scale line; diagrams option disabled and no diagram drawn; file name ends " (Bass).pdf"; a two-song songbook with a slot key override prints the overridden sounding notes; a saved fill prints as names, and as a tab with Fills as tab; walk-ups print per density; with the Chords part the output's page text and geometry are unchanged by the bass code.
- `PDFPreviewModelTests`: option change re-renders and cancels the previous render; actions disabled until ready; remembered options persist and Reset All Settings clears them; stage notes always start off; default part follows `profile.bassNotes`; analytics summary values for a session (recording adapter).
- Light pages: a page rendered while the app appearance is Dark samples a paper-white ground and `cueText` light chords (pixel sample of a rasterised page at a fixed point).
- Visual references: two rasterised pages (a single chart, a set list page) compared with the existing snapshot support's tolerance, fonts bundled.

### 14.3 P9-1c additions

- `PrintLyricsTests` (section 8.4) and `PrintMedleyTests` (section 9: set list rows "5a" / "5b", outline, "Medley 5 · 2 of 3", members flowing on without page breaks, transition blocks before each later member, member links landing on the inline header, no member header orphaned at a column foot), in-process.

### 14.4 Performance (timing budget, `make test-perf`)

`PDFRenderPerformanceTests`: a 20-song generated songbook, layout plus draw, under 1 s on Apple Silicon (the budget file's convention for the low-spec allowance).

### 14.5 E2E: `SeguePDFExportE2ETests` (new, one class, one test, P9-1c)

`testSongbookPreviewSaveAndPrint`: fresh library with the Welcome songs -> a seeded 3-song setlist with a break -> builder "Setlist" menu -> Export PDF... -> the sheet shows "Songbook PDF · 3 songs" and pages -> switch Chart to Bass notes (page count label updates) -> Save PDF... with `-SegueExportPath` pointing at a temp file -> the file exists and opens as a PDF with the expected page count -> Print... shows the system print panel -> Cancel -> Done. Added to `UITests/e2e-map.tsv` for `Packages/SegueUI/Sources/SegueUI/Export/*` and `Packages/SegueCore/Sources/Printing/*`. One `make e2e-one TEST=SeguePDFExportE2ETests`.

### 14.6 Existing tests changed

`MenuShortcuts` clash test and `KeyboardShortcuts` tests (new shortcuts), `ServicesVocabularyTests`, `LiveLayoutEngineTests` (policy flags default off), the verify scripts' fixtures if they snapshot entitlements. No existing UI test class changes.

## 15. Files owned

- New: `Packages/SegueCore/Sources/LiveLayout/PageLayout.swift`, `LiveLayout/CompactRepeats.swift`, `Packages/SegueCore/Sources/Printing/*` (new target in `SegueCore/Package.swift` and the product list), `Packages/SegueCore/Sources/Services/AnalyticsEvent+Export.swift`, `Packages/SegueUI/Sources/SegueUI/Export/*`, `Packages/SegueUI/Sources/SegueUI/App/AppModel+PDF.swift`, `AccessibilityID+PDF.swift`, tests named in section 14, `UITests/SeguePDFExportE2ETests.swift`, `guide/src/content/docs/print-and-pdf.mdx`.
- Edited (hunks only): `LiveLayout/LayoutRequest.swift` (`LayoutStyle.print`), `LiveLayout/ColumnPacking.swift` (policy flags), `Live/StageRequest.swift` (`diagrams:` parameter), `App/Commands/FileCommands.swift`, `App/MenuShortcuts.swift`, `Setlists/SetlistBuilderView.swift` (`SetlistActions`), `Setlists/SetEntryRow.swift` (slot context menu), the library song row context menu (`Library/LibraryViews.swift`), `Settings/AppModel+Settings.swift` and `DataSettingsView.swift` (reset), `Services/AnalyticsEvent.swift` (case, `ErrorCode.pdfExport`), `App/SegueLinks.swift`, the three entitlements files, `Project.swift` (the printing sandbox setting), `scripts/lib/verify-common.sh`, `docs/release/specs/WS3-services.md`, `WS1-release-pipeline.md`, `guide/astro.config.mjs`, `guide/src/data/shots.json`, `play-bass.mdx`, `build-a-set.mdx`, `section-notes.mdx`, `UITests/e2e-map.tsv`.

## 16. Sessions and steps

**P9-1a - core** (may start now; SegueCore only, plus the step 0 spike test in SegueUI)

0. Spike (decision 3): `PDFSpikeTests`. If the SwiftUI path is not vector and selectable, stop and ask (fallback: a Core Text drawer).
1. `LayoutStyle.print`, `ColumnPacker` policy flags, `PageLayout.paginate`, `PageGeometry`. Suites: `PageLayoutTests`, `LiveLayoutEngineTests`, `LiveLayoutCorpusTests`.
2. `CompactRepeats`. Suite: `CompactRepeatsTests`.
3. `Printing` target: options, document model, set list rows from `SetlistTiming`, the selection contents page (5.13), numbering, outline, links, metadata, file names. Suites: `PrintAssemblerTests`, `PrintFileNameTests`.
4. One `make quick`.

**P9-1b - drawing, viewer, Bass chart, entry points, analytics** (after P9-1a)

0. Design directions for the sheet (6.1); wait for Ryan's pick.
1. `PrintRequests` and the `StageRequest` `diagrams:` parameter; `PrintRequestParityTests`.
2. `PrintPageView`, `PDFRenderer` (pages, outline, links, attributes, light scheme). Suites: `PDFExportTests`, `PDFSongbookTests`.
3. Bass notes part, walk-ups, fills, Fills as tab, file name and keywords. Suite: `PDFBassChartTests`.
4. `PDFPreviewModel`, `PDFPreviewSheet`, `PDFKitView`, Save / Share / Print, entitlement and verify scripts, menus and shortcuts, setlist menu, slot and song context menus, the library multi-selection entry (5.13), Reset All Settings. Suites: `PDFPreviewModelTests`, the shortcut tests.
5. Analytics row and `ErrorCode`, vocabulary test, WS3 row. Performance test and the 7.3 measurement (cache only if needed). Suites: `ServicesVocabularyTests`, `PDFRenderPerformanceTests` (in `make test-perf` once).
6. One `make quick`. Launch the app on Ryan's machine at the end with a seeded setlist so he can walk through the preview.

**P9-1c - Lyrics, medleys, guide, E2E** (after P9-1b and the P9-2 / P9-3 cores)

1. Lyrics part through P9-2's transform (section 8). Suite: `PrintLyricsTests`.
2. Medley slots through P9-3's model (section 9), members flowing on. Suite: `PrintMedleyTests`.
3. Guide page and edits, `SegueLinks.Guide.pdf`, `make guide-keys`, `make guide-check`.
4. `SeguePDFExportE2ETests`; one `make quick`; one `make e2e-one TEST=SeguePDFExportE2ETests`.

## 17. Done criteria

- A song, a slot, a setlist and a library multi-selection each open in the preview from every entry point in section 4; Save, Share and Print work in the sandboxed App Store build; there is no download-only path.
- Pages are vector with selectable text, light whatever the app appearance, and match the stage for the same slot: the parity test passes, and passes, modes, badges, gig key and capo, bass notes, walk-ups and fills are the stage's.
- Every pagination rule in 5.3 holds on the fixture suite; no line pair is ever split; Compact repeats only ever replaces identical passes.
- The set list page shows slot times, part and set totals with unknown and estimated slots flagged (R172, R173), and every row links to its page; the outline matches.
- Bass notes, Lyrics (after P9-2) and medleys (after P9-3) print per sections 5.7, 8 and 9.
- A 20-song songbook re-renders within the 7.3 budget on Apple Silicon; the low-spec figure is recorded.
- Entitlements and the verify scripts agree; analytics row, guide page and links are live; the one E2E is green; all section 14 suites are green; no code depends on `SeguePersonalModules`.

## 18. Closed questions (R178, 2026-11-01)

1. **Cover page:** no separate cover; the set list page is the contents (R178; decision 9).
2. **Menu and shortcuts:** File > Export PDF... (⇧⌘E) and File > Print... (⌘P) both open the in-app preview; ⌘P inside it prints (R178; section 4).
3. **Dark pages:** light pages only (R178; 5.12).
4. **Compact repeats:** repeats are written out in full by default; only an exactly identical pass may print compactly (R178; 5.6).
5. **Diagram placement:** after the last section (R178; 5.8).
6. **Section map on paper:** the one-line text roadmap (R178; 5.5).
7. **Chord colour on paper:** `cueText` red (R178; decision 8).
8. **Margins:** fixed (R178; 5.1).
9. **Movie / Album in the header:** shown in the credits line (R178; 5.2).
10. **Songbook from a library multi-selection:** yes, as well as from a setlist (R178, differing from the spec's recommendation; 5.13).
11. **Medley members on paper:** members flow on without page breaks, with the transition note between them (R178, differing from the spec's recommendation; section 9, 5.3 rule 7).

Still open (no ruling in R176-R180): **12. Analytics extras.** (a) Row 31 as in section 11 plus `helpOpened(.pdf)`. (b) Row 31 only. Recommend (a). Close before P9-1b step 5.

## Appendix: what `docs/phases/4-export.md` said, and where it went

| `4-export.md` | Now |
|---|---|
| Scope 1-2 (single chart, songbook with cover, setlist page and TOC) | Section 4; cover and TOC merged into the set list page (decision 9, R178); songbooks also from a library multi-selection (5.13) |
| Scope 3 (print via `NSPrintOperation`) | 6.2 Print; entitlement in section 10 (missing today) |
| Scope 4 (embedded preview, options, Save / Share / Print secondary) and its Bass chart note (line 19, R161) | Section 6; Bass chart as the Chart picker's Bass notes value (5.7) |
| Rendering approach (shared `ChartLayout`, `PagePaginator`, Core Graphics + Core Text, `ChartStyle`, diagrams into `CGContext`) | Decisions 1-4: `LiveLayout` is already the shared core; `PageLayout` is the paginator; drawing via SwiftUI into a PDF context, spike-gated, Core Text fallback |
| Print theme (always light, mono-safe chords) | 5.12 and decision 8 |
| Pagination rules 1-5, 7-11 | 5.1-5.3, 5.8-5.10, 5.11; rule 10's two-pass TOC simplified (5.10) |
| Rule 6 (collapsed chorus reference) and its R147 / R158 note | 5.6 Repeats option, default Written out |
| Test strategy and acceptance criteria | Sections 14 and 17, cut to the R113 budget (one E2E) |
| Resolved decisions 1-5 | Carried forward (TOC yes, no duplex, notes opt-in, no branding footer); "ships in v0.5" is now v1.0 (R176) |
| Phase 8 hook (fills in the bass chart, P8-7 14.5) | 5.7, verified against the code (3.3) |
