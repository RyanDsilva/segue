# Phase 6 - Hands-free control (MIDI and keys)

Canonical parent: `docs/00-vision.md`. Depends on phase 2 (live mode and its command layer). Not gig-critical: the app must be fully usable without any controller. Roadmap: the first phase after v0.5 (`docs/release/decisions.md` R138); Bluetooth HID pedals and pedal presets were removed (R132); the mapping UI takes MIDI and keyboard keys with MIDI learn and key learn (R141).

## Goal

Let the performer drive live mode without touching the MacBook: MIDI controllers (foot controllers, keyboards) and keystroke-sending page-turn pedals and clickers trigger the same live-mode commands as the keyboard and trackpad, each bound to any command in one mapping UI (R141).

## Scope

- **MIDI input** through CoreMIDI from any connected source (USB, Bluetooth LE MIDI, network session, IAC/virtual).
- **One command layer.** MIDI input produces `LiveCommand` values (defined in phase 2) and adds no actions of its own. Commands in scope at minimum: next/prev page (or scroll step), next/prev song, start/pause autoscroll, scroll faster/slower, jump to top of song, toggle request queue, toggle next-song footer, toggle stage mode.
- **Mapping UI** (R141): a settings pane listing every live command with its **MIDI binding and its keyboard key binding** (either, both or none), plus **MIDI learn and key learn** ("press the pedal or key now"). Any live command can take a key, not only the ones with a default key. Learning a trigger that is already bound to another command shows the clash and offers to move it. A per-command "Restore default" and a global "Restore all defaults".
- **Page-turn pedals and clickers** (AirTurn, PageFlip, presenter clickers, BT keyboards) work through key bindings: they send keystrokes, which key learn captures like any other key. There is no dedicated pedal feature, no HID input path and no pedal presets (R132).
- **Research ticket alongside (R135):** MIDI output for per-song preset switching on an Ampero II Stomp (program change over USB MIDI and TRS MIDI, timing on song change, banks and preset numbering). Its scope (Personal module or a generic store MIDI-out) is decided after the ticket lands; until then MIDI output is not built.

## Non-goals

- **A dedicated pedal feature**: no HID (non-keyboard) pedal input path, no pedal device detection and no pedal presets ("Arrows", "Page Up/Down", "Space/Shift-Space") - removed from the roadmap (R132). Keystroke pedals and clickers are covered by key bindings and key learn (R141).
- MIDI **output** (per-song program changes) - **reopened by R135**: research ticket first, scope decided after it. Not part of this phase's build until then.
- Pedal/MIDI control **outside live mode** (editor, preview, rehearsal views) - decided: live mode only.
- Vendor apps or firmware configuration.
- Global hotkeys while Segue is in the background.
- Foot-operated text editing or any editor commands.
- Ableton Link / MIDI clock sync.

## Input handling (MIDI)

- A `MIDIInputService` creates one `MIDIClient` + input port, connects to all sources, and reacts to source add/remove notifications so hot-plugged controllers work without restart.
- Messages handled: Note On (velocity > 0), Control Change (value threshold, default >= 64 = pressed), Program Change. Bindings record (source identity or "any source", channel, message type, number).
- Parse with the MIDI 1.0 UMP-aware API (`MIDIInputPortCreateWithProtocol`). Deliver commands on the main actor.
- Entitlements: CoreMIDI input is expected to need no special entitlement in a sandboxed app (USB MIDI does not need `com.apple.security.device.usb` via CoreMIDI). Bluetooth LE MIDI pairing goes through the system Audio MIDI Setup or `CABTMIDICentralViewController` (iOS) - verify at source (see research items).

## Gestures, debounce, long-press

- **Debounce**: ignore a repeat of the same binding within 150 ms (configurable). Mechanical foot switches bounce, and some controllers double-send.
- **Long-press is opt-in, off by default.** By default every binding fires on press, instantly. A user may enable a hold command per binding (threshold 600 ms), e.g. tap = next page, hold = next song; only for that binding does the tap fire on release instead of on press, and the mapping UI says so. Long-press uses Note On/Off or CC press/release timing.
- **Double-tap**: not in v1 (adds latency to every single tap).
- All timing uses the injected clock from core so tests are deterministic.

## Key input and key learn (R141)

- Keys use the existing phase 2 binding table (`InputBindingTable`, `Shows/InputBindings.swift`): defaults in code, overrides in `bindings.json`. The mapping UI writes that file instead of the user hand-editing it; the `?` overlay and Help > Keyboard Shortcuts keep reading the same table, so they stay truthful.
- Key learn records the next keystroke with its modifiers (`KeyStroke`), shown with the same names the help uses ("Right Arrow", "Cmd-K"). Escape cancels learn; system-reserved shortcuts (Cmd-Q, Cmd-Tab, Cmd-W while on stage) cannot be learned.
- Debounce (below) applies to key triggers too, since some clickers double-send; key auto-repeat from a held key never fires a command twice.

## Mapping persistence

- One binding table for both kinds of trigger: `InputTrigger` gains a `.midi` case next to `.key`, and MIDI bindings are stored in the same `bindings.json` in Application Support (schema version bumped, with a migration), not in the song library. Controller setup is per-machine, not per-song. (This replaces the earlier separate `controls.json`.)
- Schema versioned. Unknown commands are kept but marked inactive (forward compatibility with later phases).
- Per-song overrides: not built (decided). Bindings are global per machine.

## Feedback

- A small transient HUD in live mode shows the command that fired ("Next song"). Can be turned off.
- Settings show a live "last received" indicator for MIDI, to debug a controller without guessing.

## Test strategy

Integration-first; unit tests only for the tricky timing logic.

- **MIDI integration (primary):** create a real virtual CoreMIDI source with `MIDISourceCreateWithProtocol`, drive a running live-mode session with Note/CC/PC packets, and assert the live view actually changed (page, song, autoscroll state). Cover hot-plug by creating and disposing a source mid-test, and restart persistence of a learned binding via a real `bindings.json` (R145).
- **Key learn (in-process):** drive the mapping pane's learn state with synthesized key events, assert the table and `bindings.json` round trip and that the `?` help reflects the new key.
- **Unit (narrow):** debounce and opt-in long-press state machine driven by the injected clock (tap, hold, bounce, interleaved bindings).
- **Manual E2E (recorded in the PR):** one USB MIDI foot controller through a 3-song setlist.

## Acceptance criteria

- MIDI learn binds a foot-controller CC to "next song" in two clicks. The binding survives an app restart and controller unplug/replug.
- Key learn binds a keystroke-sending pedal or clicker (e.g. Page Down) to "next page" in two clicks, for any live command; the `?` overlay shows the new key.
- A bouncy double-send within 150 ms fires once. By default every press fires instantly; only a binding with an opt-in hold command waits for release, and holding it 600 ms fires the hold command and not the tap command.
- Bindings have no effect outside live mode.
- Works in the sandboxed App Store scheme with no extra permission prompts.
- Removing all controllers leaves live mode fully usable by keyboard/trackpad.

## Research items (verify at source before building)

- Whether a sandboxed macOS 26 app needs any entitlement for CoreMIDI input from USB, BLE and network sources.
- Bluetooth LE MIDI on macOS: is pairing only via Audio MIDI Setup, or is there an in-app API?
- R135 Ampero II Stomp MIDI output ticket (see Scope).

## Resolved decisions

See `docs/decisions.md` and `docs/release/decisions.md` R132-R138 and R141.

1. **MIDI output reopened** (R135) - was "no program change / bank select on song change"; now a research ticket first, scope decided after it.
2. **Live mode only** - MIDI command dispatch is active only while live mode is frontmost.
3. **No per-song overrides** - one global mapping per machine.
4. **Long-press opt-in** - presses fire instantly by default; taps stay instant.
5. **No dedicated pedal feature and no pedal presets** (R132); keystroke pedals work through key bindings.
6. **Mapping UI takes MIDI and keys** (R141): any live command, MIDI learn and key learn, one binding table.

## Open questions

None new. The MIDI output scope waits on the R135 research ticket.
