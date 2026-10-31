# Phase 8 - in-app audio engine for hearing chords, bass notes and walk-ups (2026-10-30)

Feasibility research for R160 ("research an in-app audio engine so the user can hear chords, bass notes and candidate walk-ups, and audition and pick between walk-up options per chord change"). It feeds P8-4b (`docs/phases/8-workstreams/P8-4-bass.md`, which today lists "audio" as not in scope). **V** = verified at the cited source, or by a local probe on 2026-10-30 (macOS 26.6.2 build 25G83, MacOSX26.5 SDK, M1 Pro 16 GB); **U** = unverified.

**Scope.** This is audio *out*: synthesizing notes the chart already knows. No microphone, no ML model, no recording entitlement; playback is not a personal module.

## 0. What exists today

- **`AudioEngineClickOutput`** (`Packages/SegueUI/Sources/SegueUI/Live/MetronomeClick.swift`): one `AVAudioEngine` with one `AVAudioPlayerNode`, two synthesized 40 ms sine ticks (1760 / 1320 Hz), scheduled by host time (`AVAudioTime(hostTime:)`) on a private serial queue, built lazily on the first click, restarted when the engine stopped after a device change, follows the system default output. **V**
- **`RehearsalClick`** (same file): a 300 ms lookahead pump driven by the injectable `Clock` (Support), behind the port `MetronomeClickOutput` (`schedule(_:beat:in:)`, `stop()`). `init?(kind:)` returns nil for a gig, so a show structurally cannot make a sound (R90, R108; R142 "no metronome sound during a show"). **V**
- **`MetronomeTrack` / `MetronomeMeter`** (`SegueCore/Sources/Shows/Metronome.swift`): pure beat grid from tempo, meter and a start instant, computed not accumulated, compound meters count dotted quarters (R118). **V**
- **Tonic** (AudioKit, MIT, pinned 2.1.2 in `SegueCore/Package.swift`) already gives pitch classes and chord spelling; MIDI note numbers fall out of it. **V**
- App Store entitlements (`App/SegueAppStore.entitlements`): sandbox, user-selected read-write, network client, Shortcuts events, one app group. Audio *output* needs no entitlement (only input needs `com.apple.security.device.audio-input`). **V**

So the engine is a generalisation of something already shipped, not a new subsystem.

## 1. Engine options on macOS

| Option | What it is | Verdict |
|---|---|---|
| **AVAudioEngine + `AVAudioUnitSampler`** | Apple's sampler AU (`'samp'`) wrapped as a node. `loadSoundBankInstrument(at:program:bankMSB:bankLSB:)` takes **DLS or SF2**; `loadInstrument(at:)` takes EXS24, `.aupreset` or one audio file; `loadAudioFiles(at:)` makes one zone per file. macOS 10.10+. `overallGain` macOS 12+. **V** (SDK `AVAudioUnitSampler.h:25-91`; https://developer.apple.com/documentation/avfaudio/avaudiounitsampler) | **Adopt.** First-party, no dependency, mono-timbral so one node per voice (bass, chords). |
| `AVAudioUnitMIDISynth` | **Not an SDK class.** It is a well-known sample-code subclass of `AVAudioUnitMIDIInstrument` wrapping `kAudioUnitSubType_MIDISynth` (`'msyn'`, "fully GM-compatible multi-timbral ... DLS or SoundFont"), bank set via `kMusicDeviceProperty_SoundBankURL`. `grep` of the macOS 26.5 SDK finds no `AVAudioUnitMIDISynth`. **V** (SDK `AUComponent.h:336-356`, `AudioUnitProperties.h:3722-3755`) | Not needed: we want 2-3 fixed voices, which two samplers do with less code. |
| `kAudioUnitSubType_DLSSynth` | Desktop-only multitimbral GM synth; uses the system DLS bank by default. **V** (SDK `AUComponent.h:339`) | Same as above; and see the DLS bank caveats. |
| **Apple's `gs_instruments.dls`** | Present on macOS 26.6.2 at `/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls`, **1,996,068 bytes**, every instrument tagged "1997 Roland Corporation" (the Roland GS Sound Set). **V** (local `ls`, `strings`). The app sandbox profile grants `(read-only-and-issue-extensions (subpath "/System"))` (`/System/Library/Sandbox/Profiles/application.sb:364`) **V**, so a sandboxed app can read it; the probe loaded programs 0 and 33 in 3 ms. Licence: no public licence; it is Roland content shipped under the macOS licence, Roland's comparable Microsoft GS grant reserves "all other uses" (https://discmaster.textfiles.com/view/10495/(Vol%20F-12)%20Jun%2002%202012.iso/Essentials/DirectX9/directx%20redist.txt) **U** for Apple's terms. Loading it in place is not redistribution, but the path is undocumented (only `AVMIDIPlayer`'s "for OSX it can be set to nil for the default" bank is documented, SDK `AVMIDIPlayer.h:28-35`). Quality: 1997 GS, 2 MB total; piano peaked at 0.21 in the probe (thin, quiet). | **Fallback only, never bundled.** Fine as a zero-size "if the bundled bank fails to load" fallback, and as a dev-time placeholder. Don't make product quality depend on it. |
| **AudioKit 5** (MIT, 5.7.2 2026-03-31) | `AppleSampler` is a wrapper over `AVAudioUnitSampler` (`Sources/AudioKit/Nodes/Playback/Apple Sampler/AppleSampler+SoundFonts.swift`); `DunneAudioKit` Sampler (MIT, 5.6.2) is a C++ SFZ sampler; `SoundpipeAudioKit` (MIT, 5.7.4) has oscillators and Karplus-Strong plucks. **V** (`gh api repos/AudioKit/*`) | **Don't adopt now.** For our use it adds a 3-package dependency to wrap the same Apple AU. Keep DunneAudioKit as the escape hatch if `AVAudioUnitSampler` ever proves inadequate (e.g. SFZ banks). Verdict: build informed by it. |
| **Pure synthesized tones** | Extend today's tick generator: additive or Karplus-Strong pluck for bass, a few partials for chords, rendered to `AVAudioPCMBuffer` and scheduled on `AVAudioPlayerNode` like the click. Zero bytes, zero licences. Note: `AVAudioUnitSampler` with no bank already plays a default sine voice (probe: peak 1.00). | Good **fallback / unit-test voice**, not the product sound: a bassist auditioning a walk-up wants something that reads as a bass guitar. |
| **AUv3 hosting** | Let the user pick an installed instrument AU (`AVAudioUnitComponentManager`, `AVAudioUnit.instantiate`). Sandboxed hosts can load AUv3 (app extensions run out of process); v2 `.component` plug-ins are generally unavailable to sandboxed hosts. https://developer.apple.com/documentation/audiotoolbox/audio-unit-v3-plug-ins **U** (not probed) | **Defer.** Real complexity (UI, state, crashes in third-party code, latency) for a "nice to have" (play through my Logic bass). Revisit after v0.5 if asked for. |

**Scheduling.** `startNote` is immediate; for timed phrases use either (a) `auAudioUnit.scheduleMIDIEventListBlock` (sample-time-stamped MIDI, the SDK says "should be preferred over scheduleMIDIEventBlock going forward", `AUAudioUnit.h:640-650`) **V**, driven by the existing lookahead pump; or (b) `AVAudioSequencer(audioEngine:)` with `createAndAppendTrack()`, `AVMIDINoteEvent`, `addEvent(_:atBeat:)`, `tempoTrack`, `loopRange` and `isLoopingEnabled` (all macOS 13+, SDK `AVAudioSequencer.h:168-564`, `AVMusicEvents.h:46`) **V**. Recommend (a): it reuses `RehearsalClick`'s proven host-time pump and keeps click, bass and chords on one clock; (b) is attractive for the loop mode but owns its own tempo clock, which would drift from the click unless the click moves into the sequence too.

**Latency.** On this Mac the default output runs 512 frames at 48 kHz, device latency 70 + safety offset 74 frames, so about **13.7 ms** output latency **V** (local CoreAudio probe: `kAudioDevicePropertyBufferFrameSize` 512, range 15-4096). That is inaudible for click-to-hear auditioning. There is no `AVAudioSession` on macOS; the buffer size is per device (`kAudioDevicePropertyBufferFrameSize`) and does not need touching. USB interfaces add their own safety offsets (a few ms) **U**.

**CPU and memory (8 GB low-power Mac target).** Offline render probe (`AVAudioEngine` manual rendering, 48 kHz stereo, five 4-note chords with releases, 20 s of audio) **V**:

| Bank / program | Load | Render time for 20 s | RT share (one core) |
|---|---|---|---|
| system DLS, bass (33) / piano (0) | 3 ms | 14 / 17 ms | 0.1% |
| GeneralUser GS: piano / clean gtr / finger bass | 34 / 23 / 22 ms | 544 / 16 / 26 ms | 2.7% / 0.1% / 0.1% |
| FluidR3_GM: piano / clean gtr / finger bass | 20 / 13 / 13 ms | 55 / 53 / 14 ms | 0.3% / 0.3% / 0.1% |
| MuseScore_General: piano / clean gtr / finger bass | 52 / 13 / 12 ms | 89 / 29 / 15 ms | 0.4% / 0.1% / 0.1% |

Process max RSS for the whole GeneralUser probe was 120 MB (includes AVFoundation itself). Even the worst case (GeneralUser's heavily-modulated piano, 2.7% of one M1 Pro core) is a small fraction of an 8 GB MacBook Air / Neo-class machine; re-measure on the low-spec target before locking the bank (project rule, `segue-ai-low-power-target`). Gain staging matters: GeneralUser piano peaked at **2.90** (clipping) at velocity 100 x 4 notes, so the adapter needs per-voice gain and a limiter or headroom on the mixer.

**SF3 is not supported.** Loading MuseScore_General.sf3 (Ogg-compressed SoundFont, 39.9 MB) into `AVAudioUnitSampler` **crashed the probe process** (exit 133) **V**. Apple documents only DLS and SF2. Any bundle must be SF2 (or DLS / aupreset+CAF).

**Sandbox / App Store.** Bundled SF2 in the app's Resources is read-only and always readable. Loading a user's own SF2 later works via the existing `files.user-selected.read-write` + app-scope bookmarks. No new entitlement for output. No network. **V** (entitlements file).

## 2. Sound sources

Sizes measured by parsing each bank's `phdr/pbag/pgen/inst/ibag/igen/shdr` and summing 16-bit sample bytes per preset (`sfsize.py` scratch probe) **V**.

| Bank | File size | Licence (exact quote) | Bass (33 finger / 34 pick) | Piano (0) | Clean gtr (27) | Store OK? |
|---|---|---|---|---|---|---|
| **GeneralUser GS 2.0.3** (S. Christian Collins, 2026-02-22) https://github.com/mrbumpy409/GeneralUser-GS | 32.3 MB SF2 | "You may use GeneralUser GS without restriction for your own music creation, private or commercial. This SoundFont bank is provided to the community free of charge. Please feel free to use it in your software projects, and to modify the SoundFont bank or its packaging to suit your needs." Caveat in the same file: sample provenance "I cannot be 100% sure where all of the samples originated ... none of them came from commercially published SoundFont packages or sample CDs." (`documentation/LICENSE.txt`, License v2.0) **V** | 0.10 / 0.15 MB (short loops, heavy SF2 modulation) | 2.17 MB | 0.55 MB | Yes |
| **FluidR3_GM** (Frank Wen) https://sources.debian.org/data/main/f/fluid-soundfont/3.1-5.3/debian/copyright | 148.4 MB SF2 | "I hereby release Fluid under the MIT license, as described in COPYING." **V** | 1.33 / 1.69 MB | 7.80 MB (Yamaha Grand) | 0.73 MB | Yes (MIT notice) |
| **MuseScore_General 0.2** https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/ | 215.6 MB SF2 / 39.9 MB SF3 | "MuseScore_General.sf2 is shared under the MIT license as described in COPYING, as was FluidR3Mono and FluidR3 before it. ... The acknowledgements and copyright notices above must be included in any derivative work." (`MuseScore_General_License.md`) **V** | 1.33 / 1.69 MB (same FluidR3 samples) | 100.4 MB ("Splendid Grand", AKAI) | 0.73 MB | Yes (MIT notices); piano far too big |
| **Salamander Grand Piano v3** https://github.com/sfzinstruments/SalamanderGrandPiano | SFZ+FLAC/WAV, ~80 MB to 1.9 GB | "This work is licensed under a Creative Commons Attribution 3.0 Unported License." (repo README) **V**; a third party says it became public domain 2022-03-04 (https://github.com/educandu/abcjs-soundfonts) **U** | - | Excellent, but SFZ only (needs conversion or DunneAudioKit) and large | - | Yes with attribution; overkill |
| **Arachno SoundFont** https://www.arachnosoft.com/main/soundfont.php | 136 MB SF2 | No licence on the download page; site footer "All rights reserved. Any reproduction is forbidden without authorization." **V** (page), terms in the archive's readme **U** | - | - | - | **No** (unclear, assume not redistributable) |
| **Timbres of Heaven 3.4** (Don Allen) https://www.polyphone.io/en/soundfonts/instrument-sets/261-timbres-of-heaven-v3-4-final | ~400 MB **U** | Polyphone lists it as personal use with no further sharing **U** | - | - | - | **No** |
| Apple `gs_instruments.dls` | 2.0 MB, system | none public (section 1) | thin | thin, quiet | thin | Load in place only, never bundle |

**Recommended bundle.** Extract three presets into one small SF2 (Polyphone or a scripted extractor), keep the licence text beside it, and credit it in `THIRD_PARTY_NOTICES.md` and the website legal page (not the About window, per house rule):

- **Default: GeneralUser GS** finger bass (33), pick bass (34), grand piano (0), clean guitar (27): **about 3.0 MB** of samples (union of all eleven bass/guitar/piano presets measured was 4.7 MB). Smallest by far, good-sounding because of its modulators, and permissive. Accept the provenance caveat (25 years with no complaint, widely used commercially).
- **Alternative for a meatier bass: FluidR3_GM** (MIT, cleanest licence) finger + pick bass (3.0 MB), clean guitar (0.7 MB), and either GeneralUser's piano (2.2 MB) or Fluid's (7.8 MB). Total **about 6-11 MB**.
- **Size budget: 12 MB max** in the app bundle. Pick between the two by a blind listening A/B on bass in the first build session (a 10-minute task with the scratch probe), not by reputation.

## 3. Features and scope

| Feature | Behaviour | Notes |
|---|---|---|
| **Hear a chord** | Click (or a key) on a chord in the editor preview, library preview or the bass fretboard strip plays it: block, or a 20-30 ms strum (low to high), at **sounding pitch** (`DisplayTransform.concertSemitones`, so capo, transpose and setlist slot overrides are already in, P8-4 section 3). Voicing is a pure core function: close voicing in C3-C5 plus the bass note in the bass's range (E1-G2 for 4-string standard, B0 for 5-string, from the instrument profile's tuning). | Smallest valuable thing. |
| **Hear the bass note / line** | Same click with the bass view on plays the bass note (slash bass, else root) on the bass voice; "play the line" plays the song's bass notes in order at tempo. | Needs `BassLine` (P8-4b step 6) only for the line. |
| **Audition walk-ups (A/B)** | For a chord change, render each of the 2-4 candidates from `WalkUp` as a two-bar phrase at the song's tempo (default 90 BPM without `{tempo}`): bar 1 the departing chord with its root on 1 and the walk notes on the last beats, bar 2 the target chord on the downbeat. Candidates are labelled A-D; play one, play next, pick. Picking writes the choice (P8-4b decides where: sidecar per chord change is the natural home, never the `.cho`). | Needs `WalkUp` to return several candidates rather than one (input to the walk-ups research doc). ChordPro has no chord durations, so the phrase is a fixed audition shape, not the real bar (P8-4 already notes "beat-accurate walk-ups" are out). |
| **Play along (loop a section)** | Rehearsal loop (R148) gains optional bass and chord voices with the existing click, looping the section at tempo with the one-bar count-in. One chord per bar is the only honest default without durations; offer "chords per bar: 1 / 2" per song. | Biggest scope: timing model for chords without durations, mixer UI, loop with R148. Defer to after the first slice. |
| **Transpose and capo awareness** | All of the above read concert pitch only. A test pins `[G]` with `{capo: 2}` sounding A. | Free if the voicing reads `concertSemitones`. |

**Store vs `SeguePersonalModules`.** Everything above belongs in the **store build**: the engine is Apple-only, the recommended banks are MIT or GeneralUser's permissive licence, and nothing calls the network. Nothing here needs the personal package. The only licence-encumbered path would be bundling Arachno or Timbres of Heaven; don't. If wanted later, "Load your own SoundFont (.sf2)" in Settings works in the store build through the user-selected file entitlement, which lets a user use any bank they own without us redistributing it.

## 4. Architecture fit

Follow the click's existing shape: pure model in SegueCore, one small port, one AVFoundation adapter in SegueUI.

- **SegueCore, new `Playback` (or inside `Shows`), pure and platform-neutral:**
  - `NoteEvent { voice: .bass | .chord | .click, midiNote: UInt8, velocity: UInt8, onset: TimeInterval, duration: TimeInterval }` and `Phrase { events: [NoteEvent], length: TimeInterval }`.
  - `Voicing.chord(_ chord, concertSemitones:, range:) -> [UInt8]`, `Voicing.bass(_:tuning:)`.
  - `PhraseBuilder.chord(..., strum:)`, `.bassNote`, `.walkUp(from:to:candidate:tempo:meter:)`, later `.loop(section:tempo:meter:chordsPerBar:)`, built on `MetronomeTrack`'s grid so the click and the notes share one beat model.
- **Port** (generalising `MetronomeClickOutput`): `protocol SoundOutput: AnyObject, Sendable { func schedule(_ events: [NoteEvent], at hostDelay: TimeInterval); func stopAll() }`. Keep it this small: it has exactly one production adapter and a test recorder, which is the same justification the click port already has.
- **Adapter** `AudioEngineSoundOutput` in SegueUI (macOS, next to `MetronomeClick.swift`): **one shared `AVAudioEngine`** owning the click `AVAudioPlayerNode` and two `AVAudioUnitSampler`s (bass, chords) into the main mixer with per-voice gain. The click output becomes a client of the same engine so click and notes are scheduled on the same host clock. Built lazily on the first sound, loads the bundled SF2 off the main thread (sampler loads read from disk, "should not be called on a real time thread", SDK header), falls back to the system DLS, then to the synthesized tone.
- **Who may hold one:** a new `Audition` owner that, like `RehearsalClick`, has a failable `init?(context:)` returning nil during a gig, so no live-show code path can reach the engine (section 5).
- **Clock:** reuse `Support.Clock` and the lookahead pump (`RehearsalClick.pump`) for timed phrases and the loop; one-shot auditions schedule the whole phrase at once (they are under 5 s).
- **Deterministic tests (house rule: fast in-process tests, no new E2E for this):**
  1. Core: `PhraseBuilder` and `Voicing` tests assert note events (pitches, onsets, durations) for G->C in G, capo 2, 5-string range, compound meter. This is where the logic lives.
  2. UI: inject a recording `SoundOutput` and assert that clicking a chord schedules the expected events, that a gig context makes no `Audition`, that pressing play on candidate B stops A.
  3. Adapter smoke test: `AVAudioEngine.enableManualRenderingMode(.offline, ...)` + `renderOffline` (macOS 10.13+, SDK `AVAudioEngine.h:628-719`, https://developer.apple.com/documentation/avfaudio/audio-engine/performing-offline-audio-processing) renders a two-note phrase from the bundled bank and asserts non-silence in each onset window and silence before it, plus no clipping. The scratch probe for this doc did exactly that in under 1 s. One test, not a suite; never compare audio waveforms.

## 5. Risks

- **Sound on stage.** A wrong click in Live sending a chord to the PA is the failure that matters. Mitigations, by removing the capability rather than by policy: (1) the `Audition` owner cannot be constructed in a gig (same pattern as `RehearsalClick`, R90/R142); (2) the stage chord row has no click-to-hear at all in Live, only in Rehearsal and the editor/library; (3) entering Live calls `stopAll()` and tears the engine down. Decide whether Rehearsal stage auditions are wanted at all (open question 2).
- **USB interface as default output (Hotone Ampero II Stomp).** The Ampero II Stomp is a multi-FX with an 8-in/8-out USB audio interface per retailer listings (https://www.pmtonline.co.uk/hotone-ampero-stomp-ii) **U**. When it is the system default output (common at rehearsal and soundcheck), `AVAudioEngine` follows it, so auditions go to the amp/PA, at whatever level the pedal's USB return is set. Mitigations: an output picker in Settings ("Audition through: System output / <device>") using `kAudioOutputUnitProperty_CurrentDevice` on the engine's output unit; a quiet first-play hint when the default output's transport type (`kAudioDevicePropertyTransportType`) is USB; conservative default volume. **U** (not probed with the device).
- **Headphones / device switching.** The engine stops on a device change and posts `AVAudioEngineConfigurationChange` (https://developer.apple.com/documentation/foundation/nsnotification/name/avaudioengineconfigurationchange); the click already handles this by restarting lazily on the next schedule, which is right for auditions too (never auto-resume a loop after a device change; stop and show it stopped). Unplugging headphones switches to speakers; that is acceptable off stage.
- **Sample rate mismatch.** USB interfaces often run 44.1 or 96 kHz; connect sampler nodes with `format: nil` so the mixer converts (the probe did). Rebuild on configuration change.
- **Gain and clipping:** measured clipping with one bank (section 1); per-voice gain plus headroom.
- **GeneralUser provenance caveat** (section 2): low risk; FluidR3 is the MIT fallback.
- **SF3 crash:** never ship or accept `.sf3` in "load your own" without rejecting it up front.
- **Undocumented system DLS path** may move; only ever a fallback.

## 6. Recommendation

**AVAudioEngine + two `AVAudioUnitSampler`s + the existing click node, one shared engine, a bundled ~3-11 MB SF2 subset (GeneralUser GS by default, FluidR3 bass if it wins the listening A/B), pure phrase building in SegueCore behind a one-method-pair port, constructible only outside a gig.** No new dependency, no entitlement, store build only.

**Minimal first slice (one session):** click a chord to hear it (block/strum) and its bass note at sounding pitch in the editor preview, library preview and bass fretboard strip; audition 2-4 walk-up candidates per chord change with A/B and pick. Includes the shared engine refactor of the click, the bundled bank, the gig guard, core phrase tests, one offline render smoke test.

**Defer:** the play-along loop with bass and chords (needs a chords-without-durations timing model and R148's loop; a second session), output device picker (third, or fold into the second if the Ampero routing bites in practice), user SoundFont loading, AUv3 hosting, more instruments, swing/feel.

**Estimate: 2-3 build sessions** (1 for the first slice, 1 for play-along, up to 1 for output routing and polish), after P8-4b's `WalkUp` returns multiple candidates.

## 7. Open questions (close before the build)

1. **Bank:** (a) GeneralUser GS subset ~3 MB / (b) FluidR3 bass + GeneralUser piano and guitar ~6 MB / (c) decide by a listening A/B in the build session.
2. **Where auditions work:** (a) editor and library only / (b) also on the Rehearsal stage / (c) also Live (not recommended; contradicts R90's spirit).
3. **Walk-up pick storage:** per chord change in the song's sidecar / per setlist slot / not stored (audition only).
4. **Play-along timing without durations:** one chord per bar / per-song "chords per bar" / derive from lyric line length (fragile).
5. **Output device picker** in v0.5 or later.
6. **Chord voice:** piano only / piano and clean guitar switchable.

## Probes (scratch, not in the repo)

`/private/tmp/claude-501/-Users-ryan-Desktop-Projects-setlist/395cf4fa-87f5-4172-9e6e-ff2bd22d45d9/scratchpad/sf/scripts/` - `spike.swift` (offline render of each bank), `sfsize.py` (per-preset sample bytes), `lat.swift` (device buffer and latency).
