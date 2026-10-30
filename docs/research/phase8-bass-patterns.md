# Phase 8 research - bass walk-ups, fills and approach patterns (P8-4b)

Status: research for R160. P8-4b (`docs/phases/8-workstreams/P8-4-bass.md` section 8) is blocked on this doc and the audio-engine doc. Scope: what bassists actually play between chords in pop, rock, worship and Bollywood/Hindi covers, and what a **deterministic** generator in `MusicTheory/WalkUp.swift` should suggest. Date: 2026-10-30.

Notation used here: key of **G major** unless stated (scale G A B C D E F#), or **A minor** (A B C D E F G). Degrees are relative to the key. `|` is a barline, `.` is a held beat of the departing chord. "Approach notes" are the notes played *before* the target root, after the departing chord's root.

## 1. The pattern catalogue

| # | Pattern | Example (4/4, chord A = 1 bar) | Notes / sources |
|---|---|---|---|
| P1 | **Diatonic walk-up into IV** (1-2-3-4) | G: `G . A B` \| C | The standard country/bluegrass I-IV move; the 3-4 half step is the strongest pull. Placed on beats 3-4 ([No Treble country lesson](https://www.notreble.com/buzz/2026/01/14/country-bass-lesson-how-to-use-transitions-and-dead-notes-to-connect-a-1-4-5-groove/); TalkBass "1 1 2 3 \| 4" up or "8 7 6 5 \| 4" down, bluegrass prefers scalar over chromatic, [thread](https://www.talkbass.com/threads/bass-lines-for-bluegrass.1364204/)) |
| P2 | **Diatonic walk-up V-I** (5-6-7-1) | D: `D . E F#` \| G | Same lesson: 6-7-1 on beats 3-4, land on open or octave root |
| P3 | **Diatonic walk-down** (8-7-6-5 into IV, 1-7-6 into vi) | G: `G . F# E` \| D ; `G . . F#` \| Em | Wikipedia [Walkdown](https://en.wikipedia.org/wiki/Walkdown): G - D/F# - Em is the archetype (I - V6 - vi) |
| P4 | **Chromatic approach from below** | `G . . B` \| C ; `C . . C#` \| D | Half step below target, on a weak beat (beat 4 or an off-beat), never on 1 or 3 ([StudyBass chromatic approach](https://www.studybass.com/lessons/common-bass-patterns/chromatic-approach-notes/); [TalkingBass](https://www.talkingbass.net/approach-notes/)) |
| P5 | **Chromatic approach from above** | `G . . Db` \| C ; `D . . Db` \| C | Same sources; sounds more "jazzy/bluesy" than from below, weaker in diatonic pop |
| P6 | **Double chromatic from above** | `G . D Db` \| C | Bass Musician Magazine approach-note series ([part 5](https://bassmusicianmagazine.com/2024/01/approach-notes-part-5/amp/)); [TalkingBass double approach](https://www.talkingbass.net/using-double-approach-notes-in-your-bass-lines/). Jazz/gospel colour; rare in worship |
| P7 | **Fifth (dominant) approach** | `G . . G` \| C (G is 5 of C); `G . . A` \| D | Fifth of the *next* chord on the last quarter/eighth; implies V-I (a secondary dominant) even if the band does not play it; "keep it subtle" ([StudyBass fifth approach](https://www.studybass.com/lessons/harmony/the-fifth-approach/)). Friedland teaches lower, upper and combined dominant approaches ([review](https://bassmusicianmagazine.com/2020/02/review-hal-leonards-building-walking-bass-lines-by-ed-friedland/amp/); [Hal Leonard 695008](https://www.halleonard.com/product/695008/building-walking-bass-lines)) |
| P8 | **Scale + chromatic mix** | `G A B C#` \| D ; `C . E F#` \| G (3-#4-5) | Scale steps then a chromatic last step. StudyBass names 3-#4-5, 2-b3-3, 4-b5-5, b7-7-1 as the stock chromatic connectors; phrase ends on R, 3 or 5 ([StudyBass chromatic tones](https://www.studybass.com/lessons/harmony/chromatic-tones-in-basslines/)). No Treble's 3-4-#4-5 into V |
| P9 | **Octave / fifth pickup** | `G . . G'` (octave pop) \| C ; `G . D G'` \| C | Root-fifth-octave fill of the *departing* chord, not an approach. StudyBass "common patterns" family ([summary](https://www.studybass.com/lessons/common-bass-patterns/common-patterns-summary/)). Pop/rock/worship staple; carries no clash risk |
| P10 | **Written slash-chord line** | C - C/B - Am - Am/G - F | The line *is* the walk: C B A G F stepwise. [Lament bass](https://en.wikipedia.org/wiki/Lament_bass); [Secrets of Songwriting](https://www.secretsofsongwriting.com/2014/05/09/8-chord-progressions-with-interesting-bass-lines/) (C - G/B - Am - Am/G - F - C/E - Dm - C). Optional chromatic in-fill C B Bb A ([Ethan Hein](https://www.ethanhein.com/wp/2024/identifying-harmonized-basslines/)). Generator should add nothing inside such a line |
| P11 | **Turnaround fill** (end of a cycle back to I) | D (V): `D E F# .` \| G, or `D C B A` \| G | V-I walk up (P2) or scale walk down from 5. Also the [Walkdown](https://en.wikipedia.org/wiki/Walkdown) bars 9-10 of a 12-bar (V-IV) |
| P12 | **Fill into a new section** | last bar of pre-chorus D: `D . E F#` \| G (chorus) ; end of chorus into verse: `G F# E D` \| C | Fills mark section transitions; "less really is more"; more fills in up-tempo rock than in ballads/dub ([Yamaha, The Art of Bass Fills](https://hub.yamaha.com/guitars/bass/the-art-of-bass-fills)). Worship players use drum-like fills at phrase ends, sparingly ([TalkBass](https://www.talkbass.com/threads/bass-fills.1021818/)) |
| P13 | **Anticipation / push** | the next root on the "and" of 4 | Not a note choice; out of scope (no rhythm in ChordPro), mention only as a rhythm hint |

Walking-bass beat roles, as the textbook summarises them: beat 1 root, beats 2-3 chord or scale tones, beat 4 a "leading tone" (chromatic, diatonic or dominant) aimed at the *next* chord's root ([Dummies, walking bass](https://www.dummies.com/article/academics-the-arts/music/instruments/bass-guitar/how-to-create-a-walking-bass-line-198174/)). For pop/rock/worship the same idea shrinks to "hold the root, approach on the last one or two weak beats".

## 2. What the choice depends on

**Duration (beats of chord A).** The approach occupies the *end* of chord A, after its root has been heard. Usable slots in quarters = n - 1 (keep beat 1 for the root); with an eighth-note feel each slot holds two notes.
- n >= 4: up to 2 quarter approach notes (beats 3-4), or 3 with eighths. n >= 8 (two bars): approach only at the end of the second bar.
- n = 2: one note on beat 2 (or two eighths).
- n = 1 (a push or quick change): nothing.
- **ChordPro has no durations** (P8-4 section 1). Unknown n defaults to 2 slots, the spec's "at most two notes".

**Tempo.** Slow (< 80 bpm, ballads, worship): 8th-note runs fit, but chromatic notes stick out over sustained pads, so prefer diatonic or nothing. Mid (80-130): quarter or 8th approaches. Fast (> 140): 1-2 notes, chromatic-below or the fifth approach (quick and strong). Tempo is optional metadata (`{tempo}`); with none, assume mid.

**Genre** (genre weights for section 3):
- *Rock*: root 8ths, sparse fills, mostly into sections. Chromatic below, P8 3-#4-5, octave pops, and walk-downs into the verse. Minor-key rock leans on the bVI-bVII-i "rock cadence" (F G \| Am), where the chord roots already make the walk ([samesound reference](https://guitar.samesound.ru/en/reference/cadences/bvi-bvii-i), weak source).
- *Pop*: diatonic pickups, octave pops, fifth approach. Chromatic used lightly.
- *Worship*: the most restraint. Long roots, descending slash-chord lines (G - D/F# - Em - C), and fills only into sections. Diatonic or fifth approaches; chromatic and double chromatic sound wrong over pads ([Yamaha](https://hub.yamaha.com/guitars/bass/the-art-of-bass-fills); [TalkBass](https://www.talkbass.com/threads/bass-fills.1021818/)).
- *Country/gospel* (seen in worship and pop covers): the I-IV and V-I walk on every such change is idiomatic. A Nashville rule of thumb is to walk only when the root moves up a fourth (I-IV, V-I), not when it comes back down ([TalkBass Nashville bass](https://www.talkbass.com/threads/nashville-bass.431362/), used inconsistently even there). Gospel adds chromatic walk-ups ([PianoGroove](https://www.pianogroove.com/?p=26244)).
- *Bollywood/Hindi*: many songs are raga-derived (they use a subset of the 12 notes; [ISMIR 2013](https://archives.ismir.net/ismir2013/paper/000103.pdf)) or minor/relative-minor based ([LSA practitioner tutorial](https://loststoriesacademy.com/blogs-and-tutorials/how-to-write-chord-progressions-that-sound-like-bollywood-hits)). The harmonic-minor augmented second (b6 to 7) is idiomatic here, where in Western pop it would sound exotic. **The evidence on Bollywood bass-fill vocabulary is thin**: no pedagogical or corpus source was found. Treat these weights as provisional and tune them on the owner's own songs (section 7).

**Direction.** A walk-up raises energy (use it into a chorus or a higher section), and a walk-down settles (use it into a verse after a chorus, or I into vi/IV). For a fourth/fifth move (|d| = 5, e.g. G to C or G to D), both directions are plausible: up is the "walk-up" sound (G A B \| C), and down covers more ground in fewer notes (G F# E \| D). Rank by section energy and genre, not only the shortest distance.

**Minor keys.**
- *Natural minor* (Aeolian) is the default scale for steps between non-dominant chords: Am to F walks `G` (down) or none, and F to Am walks `G` (up).
- *The raised 7 (harmonic minor)* applies when the departing chord **is V major / V7 / vii°**. That chord contains the raised 7 (E major contains G#), so a natural G over it is a cross-relation clash. The leading tone G# into Am is the strongest approach into i.
- *Melodic minor ascending* (raised 6 and 7) is the textbook fix for the augmented second F-G# when walking up from V or iv-area to i: E `F# G#` \| Am ([Minor scale](https://en.wikipedia.org/wiki/Minor_scale)). Over an E chord, F# (its 9th) is smoother than F (its b9).
- *Genre twist*: in Bollywood or "Middle-Eastern" flavoured songs, E `F G#` \| Am (harmonic, aug 2nd) is idiomatic and should rank first there. In pop, rock and worship, `F# G#` or the single `G#` ranks first.
- Friedland's Part Two covers minor, harmonic minor and pentatonic approach material ([review](https://bassmusicianmagazine.com/2020/02/review-hal-leonards-building-walking-bass-lines-by-ed-friedland/amp/)).
- **General rule that falls out**: build the passing scale from the key's scale, then **override any letter that the departing chord A alters** (its 3rd, 5th or 7th). The passing notes sound *over chord A*, so they must agree with it. The same rule fixes major-key secondary dominants: in C, `A7` into Dm walks `B C#`, not `B C`.

**What sounds wrong or cliched.**
- A walk on *every* change, especially 1-2-3 into IV in a rock or worship song, makes it sound country ("less is more", [Yamaha](https://hub.yamaha.com/guitars/bass/the-art-of-bass-fills)). Mitigation: the spec's default density is "Into sections".
- The same walk repeated in each pass of a chorus. A human varies it, and iReal Pro and Strum Machine randomise ([iReal forum](https://forums.irealpro.com/goto/post?id=51401); [Strum Machine forum](https://community.strummachine.com/t/walking-bass-glitch-or-by-design/1088)). We stay deterministic, so the fix is a density control, not variation.
- Chromatic or double-chromatic runs over sustained pads in slow worship songs and ballads.
- Natural-minor G over an E major chord into Am (the cross-relation above).
- An approach note landing on a strong beat (StudyBass: chromatic notes need weak beats).
- Walking *into* a chord that is itself a passing slash chord (C to C/B), or adding notes inside a written stepwise line (P10). That doubles the line and clutters the chart.
- The fifth approach over-used: "if it stands out, you've overused it" ([StudyBass](https://www.studybass.com/lessons/harmony/the-fifth-approach/)).
- Tritone moves: there is no idiomatic walk. Spec rule: one chromatic note below the target.

## 3. Generator rules (chord A, n beats, chord B, key/mode, genre) -> 2-4 ranked candidates

### 3.1 Inputs and derived values

- `a`, `b`: bass pitch classes at concert pitch (slash bass else root), plus chord A's quality/tones. The spec's `notes(from:to:key:)` takes only pitch classes, so chord A's tones need to be passed in.
- `d`: signed shortest distance from a to b in -5...+6, as in the spec. Also `dUp` (1...11) and `dDown`.
- `key`: tonic + mode (major / minor), optional. `genre`: optional enum {pop, rock, worship, country/gospel, bollywood, unknown}. `beats`: optional n. `tempo`: optional. `intoSection`: Bool. `energyUp`: Bool, true when the target section is chorus/bridge, false when it is verse/outro (from section labels).
- `passScale(a, key)`: the key scale with chord A's chord-tone letters overriding it (section 2). In minor, when chord A is V/V7/vii°, use the raised 7, and the raised 6 too when walking upward to i (melodic).
- `slots`: n - 1 quarters (unknown n = 2). `maxNotes`: min(3, slots x (eighthFeel ? 2 : 1)); unknown n gives 2.

### 3.2 Suppress (return no candidates) when

1. a == b, or |d| == 1. The move is already a step (this also covers most of P10's descending slash lines).
2. B is part of a **written stepwise bass line**: the bass notes of the previous, current and next chords move by <= 2 semitones in one direction (C - C/B - Am - Am/G). The written line is the walk.
3. Chord A or B is N.C. or unknown, or A is the song's last chord (spec 8.2).
4. Known n == 1, or tempo > 160 with n <= 2.
5. Density says no: "Into sections" and A is not section-final (spec).
6. Genre is worship or ballad (tempo < 70), the move is not into a section, and the only surviving candidates are chromatic.

### 3.3 Candidate set (each candidate = notes, kind, direction)

| Kind | Notes (target b) | Valid when |
|---|---|---|
| `scaleWalk` | the passScale notes strictly between a and b in the chosen direction, the ones nearest b, at most maxNotes | 2 <= |interval in that direction| <= 7, tried both up and down |
| `scaleChrom` | scaleWalk with the last note replaced by b - 1 (going up) or b + 1 (going down), when that differs | up: last scale step into b is a whole step (e.g. 3-#4-5, `A B C#` -> D) |
| `diatonicNeighbour` | the single passScale note adjacent to b on the approach side | always (with a key) |
| `chromBelow` | b - 1 | always; it is the "no key" fallback |
| `chromAbove` | b + 1 | a is above b (descending), or genre in {rock, gospel} |
| `fifth` | the fifth of B (b + 7) | B is a new root, not a slash-chord passing move |
| `doubleChromAbove` | b + 2, b + 1 | genre in {gospel, rock}, maxNotes >= 2 |
| `octavePickup` | a's octave (and optional a's fifth before it) | section-final only; lowest priority; drawn as a fill, not an approach |

Spelling stays per the spec: key-scale notes via `KeySpelling`; chromatic notes sharp going up and flat going down. The passScale override letters keep the chord's spelling (`G#` over E).

### 3.4 Ranking (deterministic additive score; emit a per-candidate breakdown)

Score = sum of weighted terms; ties break by fixed kind order then lower pitch. Suggested starting weights:

1. **Genre prior** per kind (0-3), from this table:

   | kind | pop | rock | worship | country/gospel | bollywood | unknown |
   |---|---|---|---|---|---|---|
   | scaleWalk | 3 | 2 | 3 | 3 | 3 | 3 |
   | scaleChrom | 1 | 3 | 0 | 2 | 1 | 1 |
   | diatonicNeighbour | 2 | 2 | 2 | 2 | 2 | 2 |
   | chromBelow | 2 | 3 | 1 | 2 | 1 | 2 |
   | chromAbove | 0 | 2 | 0 | 2 | 0 | 1 |
   | fifth | 2 | 2 | 2 | 1 | 1 | 2 |
   | doubleChromAbove | 0 | 1 | 0 | 2 | 0 | 0 |
   | octavePickup | 1 | 2 | 1 | 1 | 1 | 1 |

2. **Clash with chord A** (-5): a note a half step from one of chord A's 3rd, 5th or 7th that is *not* the target-side chromatic approach note. This is how G over E-major gets rejected.
3. **Resolution** (+2): the last note is a half step from b. Whole step: +1. The fifth: +1.
4. **Direction fit** (+1): up when `energyUp`, down when not. Plus +1 for the country "walk up a fourth" case (I-IV, V-I) in country/gospel.
5. **Length fit**: -2 per note beyond `maxNotes` (and drop the candidate when it exceeds maxNotes + 1). +0.5 for using exactly the slots when n >= 4.
6. **Minor tonic** (+2): in minor with B = i, a candidate ending on the raised 7. Bollywood also gets +1 for `F G#` (aug 2nd); other genres get +1 for melodic `F# G#`.
7. **Into section** (+1 for scaleWalk/scaleChrom), so section moves get the fuller walk.

Return the top 2-4 with score >= a floor (e.g. 3). The **top-1 must equal the current spec rule's output** in its default context (unknown genre, unknown n), so `WalkUpTests` keep their meaning, *except* where this doc deliberately changes it (minor V-i). Flag that for decision.

### 3.5 Worked examples (key, genre unknown, n = 4)

| A -> B | Ranked candidates |
|---|---|
| G -> C (G) | `A B` (scaleWalk up), `B` (chromBelow = diatonic here), `G` (fifth; it is chord A's root, a "hold"), `F# E D` down (needs 3 slots, ranked low) |
| G -> D (G) | `F# E` (walk down), `A B C#` / `B C#` (scaleChrom up), `A` (fifth of D) |
| G -> Em (G) | `F#` |
| C -> D (G) | `C#` |
| E -> Am (Am) | `F# G#` (melodic), `G#`, `F G#` (Bollywood rank 1); `F G` rejected by the clash term |
| G -> Am (Am) | `G#` (spec rule); Rock: nothing better; a direct move is fine |
| F -> G -> Am (Am, rock) | F -> G: spec rule gives `F#`; proposed: nothing in rock, since the bVI-bVII-i roots already walk |
| A7 -> Dm (C) | `B C#` (chord A's C#), `C#`, `E` (fifth of Dm, rank low) |
| C -> C/B -> Am -> Am/G | nothing on any change (written line) |

(The F -> G row shows an open question, Q3 below.)

## 4. Prior art in software

| Product | What it does with bass | Licence | Worth borrowing |
|---|---|---|---|
| **iReal Pro** | 50 base styles (Jazz 27, Latin 8, Pop 15; 90 with packs), the style decides the bass ([styles](https://www.irealpro.com/learn/accompaniment-styles)). Lines are regenerated with variation on each play; users steer them mainly through chord qualities and slash chords per beat ([forum](https://forums.irealpro.com/goto/post?id=51401), [how to change bass lines](https://forums.irealpro.com/threads/how-to-change-bass-lines.14774/latest)). Some styles switch walking on or off per section. | Proprietary | Slash chords as the user's override of the generator. A per-section on/off for walking is the same idea as our "Into sections" density. |
| **Band-in-a-Box** (PG Music) | A style is "a set of rules that determine how BiaB creates music using your chords" ([manual ch.2](https://ftp.pgmusic.com/manuals/bbm2021full/chapter2.htm)). StyleMaker bass patterns are 1, 2, 4 or 8 notes long, with rules for when they play ([Sound On Sound](https://www.soundonsound.com/node/4924292)). Users report heavy editing of generated walks ([Vision Music](https://www.visionmusic.com/forum/viewtopic.php?p=196)). | Proprietary | Pattern length chosen by the chord's duration, which is our `maxNotes` from slots. |
| **Logic Pro Session Player - Bass Player** | Knobs, not note rules: Complexity/Intensity; Octaves (how often octave jumps happen); Slide Notes; Phrasing and max note length; Lowest Note (B0 = 5-string); **Align Root** = "closer intervals for root notes as it moves through the progression" ([iPad guide](https://support.apple.com/guide/logicpro-ipad/lpipd090cc55/ipados), [Mac guide](https://support.apple.com/it-ch/guide/logicpro/lgcp74b34026/mac)). | Proprietary | Align Root is the octave-placement heuristic, which matches P8-4 open question 12 (b). "Octaves" frequency is our `octavePickup` as a separate, low-ranked kind. |
| **Chordify** | Chord recognition and a chord grid. **No bass-line or walk-up generation found** (searched; nothing in public docs). | Proprietary | Nothing for walk-ups. |
| **Strum Machine** | Bluegrass/old-time backing with an upright bass that walks between chords, randomised: "there's usually more than one way to walk between chords so Strum Machine tries to mix it up" ([forum](https://community.strummachine.com/t/walking-bass-glitch-or-by-design/1088)). Slash chords for user control ([forum](https://community.strummachine.com/t/slash-chords-upright-bass-runs/868)). | Proprietary | Confirms that several valid walks exist per change. We rank them and show the top one, then audition the rest (R160) instead of randomising. |
| **Impro-Visor** (Harvey Mudd) | Style files hold weighted bass patterns built from per-beat functions (bass note, chord tone, scale tone, approach-to-next-bass-note), e.g. `(bass-pattern (rules B4 S4 C4 A4) (weight 10))`. With no pattern, no bass ([Keller slides](https://www.cs.hmc.edu/~keller/jazz/improvisor/BluesForGarySlides.pdf), [Style Editor tutorial](https://www.cs.hmc.edu/~keller/jazz/improvisor/StyleEditorTutorial.pdf)). | GPL-2.0+ ([Wikipedia](https://en.wikipedia.org/wiki/Impro-Visor), source [GitHub](https://github.com/Impro-Visor/Impro-Visor)) | **Role vocabulary**: describe a candidate as a sequence of note *functions* (scale, chromatic, approach) and resolve those to pitches. Our candidate kinds are this idea, made deterministic. |
| **MMA** (Musical MIDI Accompaniment) | CLI that builds MIDI accompaniment from a chord file and a groove library with bass and walking tracks ([home](https://www.mellowood.ca/mma/), [Debian](https://sources.debian.org/src/mma/21.09-1/text/ANNOUNCE)). | GPL (Debian package) | Text-defined grooves per genre, the same shape as our genre weight table. |
| **MIDI-Bassline-Walk / Music::Bassline::Generator** (Gene Boggs, Perl) | Randomised walking lines from chord-root scales adjusted by chord tones, with range wrapping, modal key centres, and an option to end on the next chord; the author warns of "sour notes" ([GitHub](https://github.com/ology/MIDI-Bassline-Walk), [CPAN](https://metacpan.org/release/GENE/Music-Bassline-Generator-0.0609/view/lib/Music/Bassline/Generator.pm)). | Artistic-2.0 | The sour-note warning is exactly what the chord-A clash term (3.4 #2) prevents. |
| **jmove-generator** (TypeScript) | `generateWalkingBass` from chord events, with swing/bossa/latin, rule-based with chromatic approaches (search snippet only; the repo returned 404 when fetched) ([GitHub](https://github.com/JazzMove/jmove-generator)). | Unverified | Unverified; listed for completeness. |
| **infinitewalkingbass** (JS, Tonal + Tone.js) | Browser endless walking bass ([GitHub](https://github.com/elialbert/infinitewalkingbass)). | No licence found | Tonal.js as a reference for note spelling only. |
| **accompy** (Python) | Swing style with walking bass from chord symbols ([PyPI](https://pypi.org/project/accompy/)). | Not checked | - |

Common technique across all of them: beat 1 = root (bass note of a slash chord), the last beat = an approach aimed at the next root, and the middle = chord/scale tones. Every generator that walks every bar sounds mechanical, and a 2013 open-source BiaB-replacement author notes that on fast turnarounds a real player "would probably play a single note on every chord change". Our sparse, end-of-chord-only suggestions avoid that whole class of problem. Verdict for all of them: **build informed by** (none is adoptable: wrong language, randomised, or jazz-walking rather than pop pickups).

## 5. Presenting a candidate on a chart

Constraints: glanceable on stage, it must not move the chord row, and the spec (8.3) already draws the notes small and muted after the departing chord, ending with "›".

- **Primary: note names**, key-spelled and concert pitch, matching the bass view: `G  A B ›  C`. Two or three letters fit in the chord unit.
- **Nashville view: degrees** (`1  2 3 › 4`). These are transposition-proof and match "5 · D" in P8-4a. Sharps/flats are relative to the key (`#4`, `b7`).
- **Mark chromatic notes** with a lighter weight or a small "°" so a reader sees "this note is outside the key" at a glance: `A B C#° › D`.
- **Direction glyph is optional**. The letters already show direction, and the accessibility label says "walk up A, B into C" (spec).
- **Rhythm hint (only when the chord's beats are known)**: a single prefix such as `3·4` ("on beats 3 and 4") or `&4`. Otherwise omit it: the default meaning is "the last beats before the change". Don't draw notation or tab; that is out of scope.
- **Alternatives**: show only the top candidate on the chart and stage. The 2-4 alternates live in the editor/audition popover (R160 audio doc), where a choice can be pinned per change. A pinned choice is stored in the sidecar, not the `.cho`; that needs a spec decision.

## 6. Recommended rule set for P8-4b

1. Keep the spec's distance rules as the **unknown-genre, unknown-duration top-1**: |d| <= 1 none; |d| = 2 the note between; 3-5 the nearest two passScale notes; a tritone gets a chromatic note below.
2. Replace "key scale" with **passScale = key scale overridden by chord A's tones**. In minor, this means V/V7/vii° use the raised 7, and an upward walk to i uses melodic F# G#, with harmonic F G# preferred for Bollywood. This resolves P8-4 open question 5 with a rule that is neither (a), (b) nor (c) as written.
3. Extend the API to `candidates(from:to:context:) -> [WalkUpCandidate]` (notes, kind, direction, score breakdown, degrees). `notes(...)` = `candidates(...).first?.notes ?? []`.
4. Suppression rules 3.2 #1-6, in particular **written stepwise slash lines get nothing**.
5. Genre comes from a per-song field or the user's profile default (pop if unset). It only reorders the list; it never invents notes outside 3.3.
6. Density stays as the spec has it (Off / Into sections / Every change, off by default). "Every change" still applies suppression rule 6.

## 7. Evaluation plan

1. **Golden corpus** `WalkUpCorpus.json` (in-process, `WalkUpTests`): about 60 cases of (A chord, B chord, key, mode, genre, beats?, tempo?, intoSection) -> `expectTop1`, `expectContains`, `expectNone`, `mustNotContain`. Cover:
   - every diatonic move in G major and A minor;
   - I-IV, V-I, IV-V, I-vi, vi-IV;
   - descending slash lines (C - C/B - Am - Am/G - F; G - D/F# - Em - C) -> none;
   - V-i in minor in each genre;
   - secondary dominants (A7 -> Dm, E7 -> Am in C);
   - the rock bVI-bVII-i;
   - tritone and half-step moves;
   - N.C. and the last chord;
   - flat keys (Bb, Eb) for spelling;
   - sharp keys (E, F#) for spelling;
   - known n = 1, 2, 4, 8 and unknown n.

   `mustNotContain` catches regressions (e.g. `F G` for E -> Am).
2. **Property tests** over all 12 x 12 bass pairs x 2 modes x genres:
   - output is deterministic;
   - <= 4 candidates;
   - no candidate exceeds maxNotes + 1;
   - every last note is within 2 semitones of b, or is the fifth;
   - no candidate contains b or a;
   - no note clashes with chord A's 3rd;
   - the top-1 with unknown context equals the legacy spec rule (except documented minor V-i cases).
3. **Real-song pass** (owner review, one sitting): run `BassLine.annotate` at "Every change" over the owner's library (pop, rock, worship and Hindi songs) and export a CSV of (song, A, B, top-1, alternates). Ryan marks each one good / acceptable / wrong / should-be-silent. Track **acceptance rate per genre and per kind**, and turn every "wrong" into a golden case. Target before shipping: >= 85% good-or-acceptable at top-1 and <= 5% "should be silent" misses, tuned only through the weight table.
4. **Audition check** (once the R160 audio engine exists): the same CSV played back, so judgements are by ear rather than by reading.
5. **Analytics** (non-PII): candidate kind shown, alternate picked, and suggestion turned off per genre. These show which kinds musicians reject.

## 8. Open questions for Ryan (close before P8-4b)

1. **Minor V-i**: adopt the chord-A-override rule (melodic `F# G#` top-1 for pop/rock/worship, harmonic `F G#` for Bollywood), which changes the spec's `E->Am "F G"` test? (a) yes / (b) keep natural minor / (c) research ticket with the audio engine first.
2. **Genre source**: (a) per-song field with a profile default / (b) profile default only / (c) none (one weight column).
3. **Rock bVI-bVII-i and other whole-step root moves**: (a) suggest the note between (spec) / (b) suppress in rock, where the roots already walk.
4. **Candidates surface**: (a) top-1 on the chart, alternates only in the editor audition popover / (b) cycle alternates on stage with a key.
5. **Pinned choices**: (a) store per change in the sidecar / (b) no pinning, rules only.
6. **Durations**: (a) unknown everywhere (cap 2) / (b) estimate beats from ChordPro bar lines `|` or `{time}` when present.
