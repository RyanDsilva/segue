# Phase 8 research - a corpus of abstracted bass fills (R167 Q16)

Status: research, 2026-10-30. Closes R167 Q16 ("a research ticket first: grow a corpus of real bass fills ... as abstracted patterns, never copied tabs, to drive the generator's templates"). Inputs: `docs/research/phase8-bass-patterns.md` ([BP]), `docs/research/phase8-time-model-and-fills.md` ([TM], section C3 is the generator), decisions R160-R167. Output: this doc plus the fixture `Packages/SegueCore/Tests/Fixtures/fills/fill-corpus.json` (81 examples). The requested path `Tests/SegueCoreTests/Fixtures/` does not exist; SegueCore's test resources live in `Packages/SegueCore/Tests/Fixtures/` (copied by `Package.swift` `resources: [.copy("Fixtures")]`, next to `walkups/WalkUpCorpus.json`), so the corpus sits in a `fills/` folder there.

**Short answer.** Pop/rock/worship/soul fills into sections are well attested at the level of "which notes, roughly when" in lesson pages, and they collapse into about a dozen rhythm families that map onto [TM] C3's slots with four additions (`chromaticLine`, `pentatonicRun`, `chordArpeggio`, `dominantPedal`) plus explicit `hold` and `stopTime` candidates. **Both target areas came up thin, and this doc does not hide it:** no source reached describes a Bollywood bass fill at note level, and none describes the bass notes at a key change. The key-change rows are real songs whose *modulation* is sourced (interval, kind, preparing chords) with bass notes derived from theory. The Bollywood rows are 3 song-style anchors plus 15 theory-derived idiom patterns.

## 1. Method

1. Three parallel web sweeps (Bollywood, key changes, section fills), then a host pass that re-fetched a sample of the cited pages to confirm quotes (Step Into Christmas, Born to Be My Baby, the TalkingBass fills lesson, the Secrets of Songwriting semitone article, the Classic FM key-change list, MusicMaster's Hindi bass list, Wikipedia's Tihai and Truck driver's gear change pages).
2. Sources tried: lesson sites (TalkingBass, StudyBass, No Treble, Bonedo, Bass Essentials, Posidovega, Yamaha Hub, Bass Musician Magazine, Premier Guitar, NZ Musician), songwriting/musicology (Secrets of Songwriting, Musicnotes modulation guide, Classic FM, Wikipedia, Adam Silverman, Ethan Hein), Bollywood bass blogs and Indian lesson pages, Songsterr, Ultimate Guitar, TalkBass, Reddit.
3. What blocked note-level evidence: Songsterr and Ultimate Guitar bass tabs render client-side (titles only); TalkBass returns 403; the Bollywood bass lessons are YouTube videos with no text (Sajna Ji Vaari Vaari, Bang Bang, Dilnawaz); Guitartwist's five-song Bollywood bass page does not resolve (DNS failure, twice); notation in Bonedo/Bass Musician sits in images or download-only PDFs; Premier Guitar's Day Tripper/Penny Lane pieces are paywalled.
4. **Copyright rule kept:** no tab, fret sequence or note-for-note line is copied. Each example is re-expressed as chord functions, a tick rhythm and note *functions*, and where the source only gives contour ("a fast little run", "pure Eb major pentatonic") the concrete degrees are ours and listed in `derived`.

### Evidence levels (per example)

| Level | Meaning | Count |
|---|---|---|
| `sourced` | The cited page describes this fill: its notes, contour or rhythm in words (fields we filled in are listed in `derived`) | 36 |
| `sourcedExistence` | The page confirms the musical situation (a fill at that spot, a line style, or the modulation and its preparing chords) but at most one of rhythm/notes; the abstraction is ours. Any `sourced` row whose rhythm *and* notes were both derived is automatically downgraded to this | 28 |
| `theory` | Derived from theory and the [BP]/[TM] rules; a URL, when present, supports the device (e.g. tihai), not the fill | 17 |

## 2. Counts

| Category | Total | sourced | sourcedExistence | theory | Target |
|---|---|---|---|---|---|
| Section fills (pop, rock, worship, soul, funk, gospel, blues, country) | 41 | 35 | 5 | 1 | "solid set": met |
| Key-change fills | 22 (+1 Bollywood lift = 23 rows with `modulation`) | 1 | 20 | 1 | >= 15 rows: met; **note-level evidence: 0** (thin) |
| Bollywood / Hindi film | 18 | 0 | 3 | 15 | >= 15 rows: met; **note-level evidence: 0** (thin) |
| **All** | **81** | 36 | 28 | 17 | >= 60: met |

Read the targets honestly: the row counts are met, but the Bollywood and key-change rows **drive** the templates (shape the vocabulary and give the generator a defined behaviour to test) rather than **validate** them against recordings. Section 7 says how to close that.

## 3. Schema (`fill-corpus.json`, schema 1)

Top level: `{ "schema": 1, "ticksPerQuarter": 24, "description", "families": [...closed vocabulary...], "examples": [Example] }`.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Stable, prefixed `sec-` / `kc-` / `bw-` |
| `category` | `section` \| `keyChange` \| `bollywood` | |
| `title`, `note` | string | Human description; `note` quotes or explains the source |
| `genre` | string | Descriptive (`soul`, `funk`, `gospel`, `blues`, ...) |
| `generatorGenre` | `BassGenre` raw value | `pop` `rock` `worship` `country` `bollywood` (soul -> pop, funk/blues -> rock, gospel -> country) |
| `feel` | `straight8` \| `straight16` \| `swing8` \| `shuffle` \| `compound` | |
| `tempoBand` | `slow` (< 80) \| `mid` (80-130) \| `fast` (> 130) | Tests use 70 / 105 / 150 bpm |
| `meter` | `"4/4"` \| `"6/8"` | In 6/8 a `beats` unit is an 8th (12 ticks) and a bar is 72 ticks (R118) |
| `key`, `mode` | ChordPro key, mode | `mode` adds `harmonicMinor`, `bhairav`, `majorPentatonic` beyond major/minor |
| `transition` | string | `preChorus>chorus`, `antara>mukhda`, `phrase`, `turnaround`, ... (`>` = into a new section) |
| `progression` | string | Functions across the span, `\|` = bar, `'` = new key, e.g. `bVI (= V') \| +1 -> I'` |
| `span` | `[{chord, fn, beats}]` | Departing chords in order; the last one ends at tick 0 |
| `landing` | `{chord, fn, beats}` | The target chord at tick 0 |
| `modulation` | null \| `{semitones, kind, newKey, repeats?}` | `kind`: `direct`, `dominantPrepared`, `pivot`, `commonTone`, `breakStop`, `parallel` |
| `events` | `[{at, len, n, art?}]` | `at` = ticks relative to the landing downbeat (negative = before it; > 0 = overhang); `len` ticks; `n` a note token; `art` from `slide hammer pull ghost staccato accent doubleStop` |
| `family` | closed vocabulary | The pattern family this example belongs to |
| `evidence`, `sources`, `derived` | see section 1 | `derived` lists inferred fields: `key chords rhythm notes tempo meter modulation` |
| `checks` | object | Test expectations, below |

**Note tokens** (regex in the build script; resolved to pitch classes before comparison, so `R` over Eb and `T:5` into Ab are equal):

- Over the **sounding chord** (the span chord whose window contains `at`): `R b2 2 b3 3 4 #4 b5 5 #5 b6 6 b7 7 8 b9 9`. Degrees are semitone intervals from the chord's bass (b9 = b2 an octave up, 8 = octave).
- Relative to the **target**: `T` (landing bass), `T-1..T-4`, `T+1..T+4` (semitones), `T:5` and `T:3` (fifth/third of the landing chord).
- Relative to the **new key**: `NK:1..NK:7` (diatonic degree of `modulation.newKey`).
- Generic: `S` diatonic passing tone, `C` chromatic passing tone, `CT` common tone of both chords or keys, `X` dead note, `M` melody doubling (out of generator scope).

**Checks** (what a generator test asserts; never exact notes):

| Key | Assertion |
|---|---|
| `expectFamily` | Some candidate among the generator's full list (up to 5, R167 Q11) has this family |
| `mustContain` / `mustNotContain` | That candidate's pitch classes include every / none of these tokens' pitch classes |
| `landsOn` | Its first note at `at >= 0` has this token's pitch class (`T` by default) |
| `maxNotes` | Fill notes (events before 0 that are not a span chord's root at that chord's onset) <= n; `0` = the hold candidate |
| `direction` | `up` / `down`: overall contour of the fill notes |
| `holdRanksFirst` | The `hold` ("nothing") candidate is ranked first (R162 Q1, written lines) |
| `spanTicks` | The span is this short (3/4 bar, 6/8 bar); every candidate must fit inside it |
| `overhang` | The fill may continue this many ticks past 0 (lands on the octave root first) |
| `anticipates` | The landing pitch sounds before 0 (NNS push) |
| `allowsSilence` | A `stopTime` candidate (rests, at most one pickup) must exist |
| `newKeySpelling`, `spelling` | Notes after a modulation are spelled in the new key (`{"T-1": "D#"}` going Eb -> E) |
| `passScaleKey: "new"` | Passing tones over a chord that functions in the new key (V', ii', pivot) use the new key's scale |
| `noFillBefore` | No fill notes earlier than this tick (a written line precedes it) |
| `registerStable` | Over repeated lifts, the landing note may not climb past the instrument's comfortable top |
| `cellRepeats`, `commonTone`, `minStart` | Tihai cell count; the shared note to hold; the earliest permitted start tick |
| `generatorScope` | `out` (skip: needs melody) or `partial` (double stop: check pitches only) |

**Suggested test policy.** `sourced` and `sourcedExistence` rows assert `expectFamily` and the pitch checks as hard failures. `theory` rows assert them too, but a failure there is a design question for the ear check in the editor (P8-6a audition), not a regression to "fix" blindly. Property tests from [TM] C3 step 4 still run over everything.

## 4. Findings

### 4.1 Section fills (pop, rock, worship, soul)

- **Placement is consistent across every source**: the last bar (often the last two beats) of a 4- or 8-bar phrase, landing on beat 1 of the new section ([Bonedo 6 Tipps](https://www.bonedo.de/artikel/6-tipps-fuer-bass-fills), [Posidovega](https://posidovega.com/bass-fills)). Two documented exceptions the templates must allow: a fill that **starts in the bar before last** (Gospelchops fill 1 starts on the "e" of beat 4 of the penultimate bar, tick -114, [Bonedo Gospelchops](https://www.bonedo.de/artikel/gospelchops-for-bass-gospel-bass-lernen-teil-3)), and one that **runs an 8th past the downbeat** before settling (Bonedo ex 2).
- **Chromatic lines of three into the target are the single most-cited note shape**, either direction: E-F-F# into G over a D chord on beats 3 and 4 ([Dee Murray, Step Into Christmas](https://www.notreble.com/buzz/2016/12/25/bass-transcription-dee-murray-bass-line-on-elton-john-step-into-christmas/)), "a half step the wrong way down to E, then climbs chromatically to G" ([Hugh McDonald, Born to Be My Baby](https://www.premierguitar.com/pro-advice/on-bass/on-bass-deconstructing-a-perfect-bass-line)), B-C-C# into D over A7 ([TalkingBass chromatic fills](https://www.talkingbass.net/create-killer-chromatic-bass-fills-like-pro/)), Yamaha's two-bar chromatic walkdowns/walkups into V ([Yamaha turnarounds](https://hub.yamaha.com/guitars/bass/a-bassists-guide-to-turnarounds/)). [TM] has `scaleChrom` (one chromatic last step) but no three-step chromatic family.
- **These lines break the current clash rule.** F natural over D major (Step Into Christmas) and C natural over A7 (TalkingBass) are same-letter cross-relations, exactly what R165's clash term penalises, yet both are sourced idioms. The exemption that falls out: a note inside a monotonic chromatic run that ends on the target, on a weak 8th/16th, is not a clash.
- **Pentatonic runs of the departing chord** are the rock/pop staple (Kershaw's E minor pentatonic fill bar, Genesis' Eb major pentatonic 16ths, TalkingBass's C# minor pentatonic fills, Bass Essentials' Em pentatonic plus a chromatic #4, Bonedo's A minor blues scale). They are chord-scale material, not target-directed; most end on a chord tone of the target or on its fifth (Bonedo ex 1 ends on A, the 5 of D7).
- **Motown/soul uses the single chromatic approach, pushed**: Jamerson approaches Abm7 from G "not Gb" ([NZ Musician](https://nzmusician.co.nz/lessons/funk-meets-jazz-%c2%96-james-jamerson-1936-1983/)), i.e. chromatic beats diatonic. This is [BP] `chromBelow`; the corpus adds the 8th-early push.
- **Arpeggio fills of a V7** (TalkingBass beginners fills 1-2; the Deacon/Palladino R-5-9 lick) are a real family that is neither a walk nor a run.
- **Restraint is sourced, not assumed**: worship and ballad practice is "less is more" ([Yamaha art of fills](https://hub.yamaha.com/guitars/bass/the-art-of-bass-fills)); written slash lines are the walk ([Walkdown](https://en.wikipedia.org/wiki/Walkdown)). A `hold` candidate must exist and rank first there.
- **Rhythm-only fills** exist and are common: the 16th pickup before each heavy downbeat (Mother's Finest), the anticipation of a chord change on the "and" (Livin' on a Prayer), the Beatles "machine-gun" repeated note into a section ([Beatles Bible](https://www.beatlesbible.com/forum/recording-and-musicology/machine-gun-bass/)).

### 4.2 Key changes

- **Sourced at song level** (interval and kind): Man in the Mirror G -> Ab, direct ([Wikipedia](https://en.wikipedia.org/wiki/Man_in_the_Mirror), [Secrets of Songwriting](https://www.secretsofsongwriting.com/2014/06/06/adding-a-semitone-upward-key-change-to-your-song/)); Love on Top, four +1 lifts ([Wikipedia](https://en.wikipedia.org/wiki/Love_on_Top), [Silverman](https://adambsilverman.com/2015/03/decoding-the-love-on-top-modulations/)); I Will Always Love You A -> B; Come On Eileen C -> D; Livin' on a Prayer +3 with a 3/4 bar just before it ([Classic FM](https://www.classicfm.com/discover-music/music-theory/best-key-changes-in-pop-music/)); A Lover's Concerto C -> Db through Ab, the new key's V; Hello, I Love You abrupt +1; The Show Must Go On Bm -> C#m; Street Life +1 twice; Because the Night +2 ([Wikipedia](https://en.wikipedia.org/wiki/Truck_driver%27s_gear_change)); pivot cases Save Me, Happy Together, Mirrors ([Musicnotes](https://www.musicnotes.com/now/tips/a-complete-guide-to-musical-modulation/)); three prepared-lift recipes (bVII/bvii route, augmented 6th as V, bIII as ii of the new key) from Secrets of Songwriting.
- **The only sourced statement about the bass at a lift** is that it simply moves with the band: Livin' on a Prayer's "bass pattern simply shifts up three frets" ([Bass Musician](https://bassmusicianmagazine.com/?p=18846)), and No Treble's advice to learn "the chorus bass line in the new key" ([No Treble](https://www.notreble.com/buzz/2019/03/29/the-lightbulb-moment-one-song-to-learn/)). So **"no fill, just land in the new key" must be a first-class candidate at a lift**, not a fallback.
- **Forum cues** (search-snippet level): a half-step lift is often cued by the old key's #5 (= the new key's V), a whole-step lift by #1/II (= V of the new key) ([The Fretboard](https://thefretboard.co.uk/discussion/comment/162099)); "play ii and V of the new key before the change" ([TAXI forum](https://forums.taxi.com/post121753.html)).
- **Structural facts the generator can exploit (theory, consistent with every row):**
  - A **+1 direct lift gives the chromatic approach for free**: the old tonic is the new root's T-1. The cheapest idiomatic fill is old root (or its octave) on 4 or 4& -> land.
  - In a **dominant-prepared lift** the preparing chord's 3rd is the new leading tone (Ab's C into Db; E's G# into A), so an arpeggio of that V' already ends on T-1.
  - In a **+2 lift** the new key's 5 (T:5) and 7 (NK:7) are the strong cues; NK:7 is a cross-relation with the old key (C# against C), acceptable only as the last weak note.
  - **Spelling flips with the key**: T-1 into E after Eb is D#, not Eb.
  - **Parallel/pivot changes** need passing tones from the *new* mode (Happy Together: A#, not A, walking B -> F#).
  - Repeated lifts (Love on Top x4) drift upward: the octave choice must keep the register stable.

### 4.3 Bollywood / Hindi film

- **Sourced (line style only, [MusicMaster](https://musicmaster.in/blog/top-10-bass-guitar-hindi-songs/))**: Dum Maro Dum "mostly outlines the root and fifth, with passing notes" in a hypnotic loop; Rock N Roll Soniye uses "a walking rhythm, progressing through the I-IV-V"; Koi Kahe Kehta Rahe is "always in motion", staccato and kick-locked; Ruby Ruby and Aap Jaisa Koi are bass-led grooves; Yeh Jo Des Hai Tera and Dhak Dhak keep the bass low-profile. Songsterr lists bass play-alongs for Dil Se Re, Chura Liya, Mehbooba, Aap Jaisa Koi and others ([listing](https://www.songsterr.com/a/wsa/djmistryman-tabs-a201661?inst=bass)) but did not render them.
- **Not supported by any source reached** (kept as `theory`): harmonic-minor V-i runs with the augmented second, raga-mode runs (Bhairav b2-3), tihai cadences on the bass, dadra 6/8 pickups, bhangra/chaal swing pickups, interlude hooks doubled in octaves, slides in ballads, last-mukhda semitone lifts. Each is musically well-founded (film songs are often raga-derived, [ISMIR 2013](https://archives.ismir.net/ismir2013/paper/000103.pdf); a tihai is "a rhythmic pattern played three times ... its final beat lands on the sum", [Wikipedia](https://en.wikipedia.org/wiki/Tihai)), but none is attested *as a film bass fill*.
- **No Hindi film song with a documented key lift was found** (searched in both the Bollywood and key-change sweeps).

## 5. Pattern families and how they map onto the generator's template slots

[TM] C3 slot functions: `R` root, `C` chord tone, `S` passing scale tone, `A` approach to next, `O` octave, `P` pivot/common tone, `D` dominant of the next. Ticks are the canonical shape in 4/4 (scale by span; 6/8 maps 8ths to 12-tick slots).

| Family | n | Rhythm (ticks before 0) | Slot sequence | Genres seen | [TM] C3 status |
|---|---|---|---|---|---|
| `pickup8` | 10 | -24, -12 (sometimes -36 too) | C/O, A | pop, rock, key changes, Bollywood | exists |
| `chromaticLine` | 8 | -36 -24 -12 or -48 -36 -24 (8ths/quarters) | A3 A2 A1 (T-3 T-2 T-1, or T+3..T+1 descending) | rock, pop, soul, blues, key changes | **add** (C3 has only one chromatic step) |
| `quarterWalk` | 8 | -72 -48 -24 (or full bar) | S S A, or C C C S (boogie) | country, pop, pivot modulations, Bollywood | exists |
| `pentatonicRun` | 8 | 16ths over the last 1-2 beats, or 8ths over a bar | pentatonic/blues of the sounding chord, ends on a chord tone or T:5 | rock, pop, R&B, Bollywood folk | **add** (needs a scale source other than passScale) |
| `dominantApproach` | 5 | -24 or -12 (single) or -48 -24 | D, or D then A (V' arpeggio) | pop, worship, key lifts | exists as a slot, **add as family** |
| `hold` | 5 | none | none | worship, written lines, lift with no fill, bVI-bVII-i | **add explicitly** (C3 mentions "hold" only for written lines) |
| `rootFiveOctave` | 4 | -48 -24 or 16ths on 4 | R C(5) O | pop, rock, Bollywood ostinato | exists |
| `scaleRun` | 4 | 8ths/16ths over 2 beats | S... ending A or T+2 | worship, rock, gospel, harmonic minor | merge into `sixteenRun`/8th runs as a direction-aware scale run |
| `slideInto` | 4 | -12 slide | A (T-1 / T-2 / octave) with `slide` | rock, Bollywood ballad, +1 lift | **add** (an articulation on a 1-note template) |
| `approachNote` | 4 | -24 or -12 | A | soul, +1 lifts, worship | equals the walk-up single note; keep as the minimal fill |
| `sixteenRun` | 3 | 4-8 16ths, may start off-beat (-114) | S/C runs | rock, gospel, Bollywood harmonic minor | exists; allow off-beat starts |
| `restPickup` | 3 | single 16th or 8th before 0 | A or R | funk, Bollywood staccato, chaal | exists |
| `octavePops` | 3 | 16ths/8ths R O R O | R O | funk, rock, filmi disco | exists |
| `anticipation` | 2 | landing at -12 | T early | rock, soul lift | exists (plus `push` in the timeline) |
| `chordArpeggio` | 2 | 8ths over the bar or quarters | R C C C O C C C | pop V7 -> I, Deacon/Palladino | **add** |
| `stopTime` | 2 | hit on 1, rests, optional pickup | R (staccato) ... A | rock, lift after a break | **add** (silence as a candidate) |
| `tripletRun` | 1 | 16th triplets on beat 4 (4-tick grid) | C C O C C C | pop | exists |
| `dominantPedal` | 1 | repeated 8ths of V' | D D D D | prepared half-step lift | **add** (key changes only) |
| `turnaround` | 1 | one root per 2-beat chord + A | R R R R A | blues | not a template: a span shape the generator should recognise and leave as roots + approach |
| `tihai` | 1 | 3 x (3 16ths + 1 rest), last note on 0 | cell ending on T, three times | Bollywood | **add** (genre-gated, low prior) |
| `machineGun` | 1 | 4 x 16th same note | O O O O | rock (Beatles) | optional, low prior |
| `melodicUnison` | 1 | follows the melody | M | Bollywood interludes | **out of scope** (needs the melody) |

`dottedPush` and `halfTimeHold` from [TM] C3 got **no** corpus support; fold `halfTimeHold` into `hold` and keep `dottedPush` only if the ear check wants it.

**Strongest families** (frequency x number of independent sources x genres): `chromaticLine`, `pentatonicRun`, `pickup8`, `quarterWalk`, then `hold` and `dominantApproach`.

## 6. Recommended generator template changes (c)

1. **Add `chromaticLine`** (2-3 consecutive semitones ending on T, from below or above, 8ths or quarters) and **exempt its inner notes from the R165 clash term** when they are on weak sub-beats and the run is monotonic into T. Sourced by four independent examples that the current clash rule would reject.
2. **Add `pentatonicRun`** with its own scale source: the sounding chord's major/minor pentatonic or blues scale (chosen by chord quality and genre), ending on a chord tone of the landing chord or its 5. Rock/pop/R&B prior high, worship low.
3. **Make `hold` an explicit candidate for every span**, ranked first for written stepwise lines, bVI-bVII-i (R162 Q1), slow worship, and as a top-two candidate at **any** key change ("the pattern just moves up").
4. **Key-change slot rules**: resolve `S` passing tones over a chord that functions in the new key (V', ii', the pivot) from the **new key's scale**; add `NK:n` resolution; spell everything after the change in the new key; for `+1 direct`, emit the old root/octave as the free `A` (T-1); for prepared lifts, prefer an arpeggio of V' that ends on its 3rd (= T-1); add a `dominantPedal` family (repeated V' 8ths) for prepared lifts; allow `NK:7` as a cross-relation only as the last weak note.
5. **Add `stopTime`** (hit + rests + optional one-note pickup) and **`chordArpeggio`** (V7 up/down) as families; **`slideInto`** as an articulation variant of the one-note templates (`approachNote`, `octavePops`).
6. **Genre-gated Bollywood families**: `tihai` (cell ending on T, last note on 0), harmonic-minor and raga-aware `passScale` via a per-song `mode` (harmonic minor, Bhairav, pentatonic) so the augmented second ranks first for `bollywood` and is never flagged as a clash there.
7. **Fit templates to the real span**: short bars (a 3/4 bar = 72 ticks before a lift), 6/8 compound grids (12-tick 8ths, pickups on the last three 8ths), off-beat starts up to about a bar and a quarter before 0, and an optional `overhang` (fill continues through the downbeat on the octave root).
8. **Register stability**: across consecutive lifts or repeated fills, choose the octave that keeps the landing note within the profile's range rather than always the nearest upward.

## 7. Gaps and next steps

- **Bollywood fills: thin.** Zero note-level sources. Best next sources: Songsterr bass tracks via a real browser session (rendered notation; abstract, never copy), the Guitartwist five-song page when its DNS resolves, the Hindi YouTube lessons watched by a human, interviews with Loy Mendonsa, Keba Jeremiah or Guy Pratt, and **Ryan's own Hindi library** judged by ear in the P8-6a audition loop (R162 Q5 already moved judging to the ear). Each confirmed fill becomes a `sourced` or owner-confirmed row.
- **Key-change fills: thin at the bass level.** Modulations are well sourced; bass behaviour at the lift is not. The Musicnotes and Bass Musician PDFs, Rubin's *Motown Bass* and Slutsky's *Standing in the Shadows of Motown* (offline books) are the likely places for real lift fills; worship lifts are best confirmed from WorshipOnline-style bass tutorials (paywalled).
- **Meter and tempo** are almost never stated by fill sources; the corpus's tempo bands are mostly ours (`derived` does not list `tempo` for every such row, since the band is a coarse category).
- **Out of scope for a chord-only generator:** melody doubling (`melodicUnison`) and double stops (checked as pitches only).
- The corpus has one `turnaround` row; if turnarounds matter beyond blues, add a span-shape rule rather than a template.
