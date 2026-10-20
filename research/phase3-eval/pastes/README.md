# Ryan's real pastes (local only, never committed)

This folder holds 10-20 real chord-sheet pastes that re-validate the curated MLX model before it is locked (R64, workstream P3-A). They contain copyrighted lyrics, so **everything here except this README is gitignored** (`.gitignore`: `research/phase3-eval/pastes/*` with `!research/phase3-eval/pastes/README.md`). Never quote them in docs, commit messages, issues or chats; results are reported as aggregate numbers only.

## Format

- **One `.txt` per paste**, exactly as copied from the source (do not tidy it: the mess is the test). UTF-8 or whatever the clipboard gave you.
- **Name:** `E01-<short-slug>.txt` for English, `H01-<short-slug>.txt` for romanized Hindi / Hinglish. The slug is just for you.
- **Optional expected result:** `<same name>.cho` next to it, the song as you would want it after cleanup: `{title}`, `{artist}`, `{key}` and sections (`{start_of_verse}`, `{start_of_chorus}`, `{start_of_bridge}`, ... or `{start_of_verse: Intro}` style labels). Without a `.cho`, the P3-A session drafts the expected labels and asks you to confirm them.

## What to include

- Mostly Ultimate Guitar pastes, plus other sites you actually use (any chord site, a PDF copied as text, a notes-app sheet).
- At least 4-5 Hinglish songs, some heavy on Hindi words, some code-mixed.
- A few deliberately messy ones: web junk around the song, tabs mixed in, no section headers, `x2` repeats, capo notes.

## Fetched pastes and gold conventions

- Besides Ryan's own copies (named by slug only), `E01-*`/`H01-*` files may be fetched from chord sites by an agent: low volume, robots.txt respected, no bot-protection bypass. Each is rendered as a browser select-and-copy of the page would give it, including the site's title/artist heading and the junk a real selection picks up (capo/key lines, strumming widgets, ratings, share buttons, credits).
- Gold lives in `../gold.local.json`, one entry per file stem, with one label per block **as the P3-1 pipeline segments the paste** (get block indices from `fmspike render`/`dump` with `SPIKE_SEGMENTER=ingest`). Labels: `intro verse prechorus chorus bridge instrumental outro other`; a list accepts any of its labels and its index goes in `ambiguousBlocks`.
- Labels follow what the section is, not the site's header (e.g. a UG `[Bridge]` that is really the pre-chorus accepts both). Page junk, strumming widgets and chord legends are `other`.
- `title`/`artist` may be a list of accepted spellings; `null` means the paste does not state it. UG's "Misc Soundtrack" is not an artist, so those entries are `null` unless a body line names the singer.
- `key`: for capo or retuned songs accept both the shape key and the sounding key; `keyStated` is true when the paste writes a key.

Gold data and results derived from these files (`../gold.local.json`, `../results/`) are gitignored too, because they name real songs.
