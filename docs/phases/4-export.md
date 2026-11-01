# Phase 4 - Export & Print (retired)

This plan is retired. The one canonical spec for PDF export, print and the embedded preview is **[`docs/phases/9-workstreams/P9-1-pdf-export.md`](9-workstreams/P9-1-pdf-export.md)** (R176: built for v1.0). It was verified against the code on 2026-10-31 and carries every resolved Phase 4 decision forward (`docs/decisions.md` Phase 4: table of contents, no duplex, notes opt-in per export, no branding footer).

Older specs cite parts of this file. They now live here:

- "Scope 4" (the embedded preview, its options, Save / Share / Print as secondary actions) and the Bass chart note at line 19 (R161): P9-1 sections 5.7 and 6.
- "Rendering approach" (shared layout core, `ChartLayout`, `PagePaginator`, `ChartStyle`): P9-1 decisions 1-4 and section 7.
- "Print theme": P9-1 decision 8 and section 5.12.
- Pagination rule 6 (repeats) and its R147 / R158 P8-2 Q9 note: P9-1 section 5.6 (the PDF repeats option, default written out in full).
- The Phase 8 hook for fills in the bass chart (P8-7 section 14.5): P9-1 section 5.7.
- "Test strategy" and "Acceptance criteria": P9-1 sections 14 and 17.

The full mapping from this plan's rules to the new sections is the appendix of P9-1.
