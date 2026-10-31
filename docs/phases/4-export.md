# Phase 4 - Export & Print

> Canonical parent: `docs/00-vision.md`. Research: `docs/research.md`. This doc is standalone - a build session should not need anything else, apart from the phase 0-2 code it extends.

## Goal

Get charts and setlists out of Segue as paper or shareable PDFs. **Ships in v0.5.** Exports must look as good as the live view and must match what the performer currently sees: transpose, capo, Nashville and diagram settings.

## Scope

1. **Single chart PDF** - one song, current display settings applied.
2. **Songbook PDF** - a whole setlist as one document:
   - cover page with setlist name, date and venue (if set);
   - a setlist page with song order, key and capo;
   - a **table of contents** with page numbers (can share the setlist page when it fits; TOC entries are PDF outline/bookmark links too);
   - then each song, starting on a new page.
3. **Print** - both PDF types go through the macOS print panel (`NSPrintOperation` with the PDF as the source).
4. **Embedded preview** - every export opens in an in-app PDF viewer (`PDFView` wrapped for SwiftUI). The viewer has toolbar options (paper size, display toggles, include diagrams, include notes) and re-renders live when they change. Save, Share (`ShareLink` / `NSSharingServicePicker`) and Print are secondary actions in the viewer. There is no download-only path.
   - *Note (2026-10-30): the "Bass chart" toolbar option (R158 P8-4 Q8, spec `docs/phases/8-workstreams/P8-4-bass.md` section 7.4) is part of this phase's build: P8-4a reached its step 3c before this export existed, so the toggle, its rendering through `DisplayOptions.withBass(_:forcingNotes:)`, the " (Bass)" file name, the "bass chart" keyword, the `bassChart` analytics key and the tests in P8-4 section 11.5 move here (R161). P8-4a already provides everything below the toggle.*

## Non-goals

- Exporting to other apps' formats (e.g. Word).
- Email/cloud upload integrations beyond the system share sheet.
- Annotations or handwriting on PDFs.
- Per-band-member part exports.

## Rendering approach

**Options**

1. **Reuse the live-view layout engine.** The live view (phase 2) already lays a parsed song out into blocks: section, line with chords, diagram strip. Export would reuse those blocks but paginate them onto fixed-size pages instead of auto-fitting one screen.
2. **A separate paginated renderer** written directly in Core Graphics/Core Text.

**Analysis**

- The live view optimises for one screen: it fits to the screen, scales and uses columns. Print needs fixed page sizes, page breaks, headers and footers. That argues for different *pagination*.
- The *measurement and drawing* of a chord-over-lyric line must stay identical, though, or exports will drift from what is on stage. That argues for a shared engine.
- **Recommendation: split the two.** One shared, platform-neutral layout core (`ChartLayout` in SegueCore or SegueUI) turns a song plus display settings into measured blocks. Two thin consumers sit on top: the live-view fitter (phase 2) and a `PagePaginator` (this phase). If phase 2 shipped the fitter without that separation, this phase extracts it.

**Drawing backend**

| Option | Pros | Cons |
|---|---|---|
| SwiftUI `ImageRenderer` into a PDF context | Reuses SwiftUI chart views as-is | Rasterises some effects; weak control over page breaks; has to be driven one page at a time anyway; text selectability uncertain |
| Core Graphics PDF context (`CGContext(consumer:mediaBox:)`) + Core Text | Vector, selectable text, exact control, deterministic | More drawing code |
| PDFKit (`PDFDocument`) | Good for viewing, merging, metadata | Not a layout or drawing API |

**Recommendation:**

- Draw with **Core Graphics + Core Text**, using the shared block measurements.
- Use **PDFKit** only to view the result, merge pages and set metadata (title, author, keywords set to tags).
- The SwiftUI views and the PDF drawing both take their fonts, colors and metrics from a single `ChartStyle` value.
- Chord diagrams (phase 1) must be able to draw into a `CGContext`, not only as SwiftUI views.

**Print theme**

- Always light: black text, with a dark-ink chord colour that stays readable on a mono printer.
- This is separate from the dark stage theme. Section styling from the live view is kept, as a light tint or a rule line.

## Pagination rules

1. Paper sizes: A4 and US Letter. The default comes from the system locale; margins are configurable.
2. Every page has a header: title, artist, key, capo. Continuation pages show "title (cont.)". The footer shows "page n/m" and, in a songbook, the song's position in the set.
3. The smallest unit that can be split is a **chord+lyric line pair**. It is never split.
4. Sections are kept whole whenever they fit on a page. If a section doesn't fit in the remaining space but does fit on an empty page, it moves to the next page. If it is longer than a full page, it breaks between line pairs, and the section label repeats as "Chorus (cont.)".
5. A section heading is never orphaned at the bottom of a page: it needs at least 2 line pairs with it.
6. A collapsed chorus repeat (the "Chorus" reference block) prints as the reference when the live view collapses it. An export option expands it in full.
   - *Note (2026-10-30): the live collapse setting this rule leans on is removed; the stage writes every repeat out in full (R147). The PDF export gets its own repeats option instead, default written out in full (R158, P8-2 Q9).*
7. Diagram strip: either on top of the first page or at the end of the song (an option). It is never split.
8. Fit-to-one-page option for single charts: try 2 columns, then scale the font down to a minimum readable size (configurable, default 9 pt). If it still doesn't fit, fall back to multi-page.
9. Songbook: each song starts on a new page. No duplex padding (decided: not supported).
10. TOC: two-pass render - paginate songs first to learn start pages, then lay out the TOC; if the TOC itself spans pages, re-offset and re-render once.
11. Per-song notes/cues are **opt-in per export** (off by default; they may be private reminders). No branding footer.

## Test strategy

Integration-first: exercise the real parser, real library files, real `ChartLayout`, real paginator and real Core Graphics/PDFKit output. Unit tests only where the logic is tricky and pure.

- **Export integration tests (primary):** load fixture songs from a temp library folder (short, long, chords only, tabs, transposed, Nashville, with diagrams), export each PDF type end to end, then assert via PDFKit: page count, outline/TOC entries and their target pages, extracted text contains the expected chords in transposed/Nashville form, no line pair split across pages, metadata.
- **Visual snapshots:** rasterise each page at fixed DPI and compare to reference PNGs with a small tolerance; fonts bundled for determinism.
- **Paginator unit tests (narrow):** only the tricky pure cases - over-long section, orphan heading, fit-to-one-page fallback, TOC re-offset.
- **E2E (XCUITest):** open a setlist, open the songbook preview, toggle capo, preview updates, save to a temp folder, assert a valid PDF exists.

## Acceptance criteria

- Both PDF types render with vector, selectable text and correct metadata.
- Exports reflect the current transpose, capo, Nashville and diagram settings. Changing a toggle in the preview re-renders in under 1 s for a 20-song setlist on Apple Silicon.
- No line pair is ever split, and the section-keeping rules hold on the fixture suite.
- Print works through the system panel. Save and Share work in the sandbox, using the user-selected destination or the share sheet.
- All export code runs in the App Store scheme; there is no dependency on personal modules.

## Resolved decisions

See `docs/decisions.md`.

1. **Table of contents: yes**, with page numbers and PDF outline links - requires the two-pass render (rule 10).
2. **Duplex: no** - songs start on a new page, no blank padding.
3. **Notes in export: opt-in per export** - default off, toggle in preview toolbar.
4. **No branding footer.**
5. **Ships in v0.5.**

## Open questions

None new.

Phase 8 hook (R167, R168): the bass chart PDF also prints saved bass fills as note names or tab; see docs/phases/8-workstreams/P8-7-time-model-and-fills.md section 14.5.
