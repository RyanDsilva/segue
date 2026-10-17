# Phase 6 - Hands-free control (pedals + MIDI)

Canonical parent: `docs/00-vision.md`. Depends on phase 2 (live mode and its command layer). Not gig-critical: the app must be fully usable without any controller.

## Goal

Let the performer drive live mode without touching the MacBook: Bluetooth page-turn pedals and MIDI controllers (foot controllers, keyboards) trigger the same live-mode commands as the keyboard and trackpad.

## Scope

- **Bluetooth HID pedals** (AirTurn, PageFlip, generic BT keyboards/clickers). These pair with macOS as keyboards and send ordinary key events. No vendor SDK.
- **MIDI input** through CoreMIDI from any connected source (USB, Bluetooth LE MIDI, network session, IAC/virtual).
- **One command layer.** Both input kinds produce `LiveCommand` values (defined in phase 2). Neither adds its own actions. Commands in scope at minimum: next/prev page (or scroll step), next/prev song, start/pause autoscroll, scroll faster/slower, jump to top of song, toggle request queue, toggle next-song footer, toggle stage mode.
- **Mapping UI**: a settings pane listing every command with its key and MIDI bindings, plus **MIDI learn** ("press the pedal now") and key learn.
- **Presets** for common pedal modes so most users never open the mapping table.

## Non-goals

- MIDI **output** (per-song program changes for keyboards/effects) - decided: not built.
- Pedal/MIDI control **outside live mode** (editor, preview, rehearsal views) - decided: live mode only.
- Vendor apps or firmware configuration (AirTurn Manager etc.).
- Global hotkeys while Segue is in the background.
- Foot-operated text editing or any editor commands.
- Ableton Link / MIDI clock sync.

## Input handling

### Key events (pedals)

- Capture with an app-level `NSEvent.addLocalMonitorForEvents(matching: .keyDown/.keyUp)` that is active only while live mode is frontmost. Local monitors need no Accessibility/Input Monitoring permission and work under App Sandbox. Never use a global monitor or a CGEventTap.
- Pedal modes differ by vendor and switch position: arrow keys (Up/Down or Left/Right), Page Up/Down, Space/Return, or media keys. Ship presets: "Arrows", "Page Up/Down", "Space/Shift-Space", "Custom".
- Pedal keys must not leak into focused text fields (search box, notes). While live mode owns input, matched keys are consumed. When the request-queue search field is focused, pedal bindings stay active only for keys that cannot type text (arrows, page keys).
- Key repeat: ignore `isARepeat` events by default. Some pedals emit repeat on long hold, so long-press is detected from keyDown/keyUp timing, not repeats.

### MIDI

- A `MIDIInputService` creates one `MIDIClient` + input port, connects to all sources, and reacts to source add/remove notifications so hot-plugged controllers work without restart.
- Messages handled: Note On (velocity > 0), Control Change (value threshold, default >= 64 = pressed), Program Change. Bindings record (source identity or "any source", channel, message type, number).
- Parse with the MIDI 1.0 UMP-aware API (`MIDIInputPortCreateWithProtocol`). Deliver commands on the main actor.
- Entitlements: CoreMIDI input is expected to need no special entitlement in a sandboxed app (USB MIDI does not need `com.apple.security.device.usb` via CoreMIDI). Bluetooth LE MIDI pairing goes through the system Audio MIDI Setup or `CABTMIDICentralViewController` (iOS) - verify at source (see research items).

## Gestures, debounce, long-press

- **Debounce**: ignore a repeat of the same binding within 150 ms (configurable). Mechanical pedals bounce, and some BT pedals double-send.
- **Long-press is opt-in, off in every preset.** By default every binding fires on press, instantly. A user may enable a hold command per binding (threshold 600 ms), e.g. tap = next page, hold = next song; only for that binding does the tap fire on release instead of on press, and the mapping UI says so.
- **Double-tap**: not in v1 (adds latency to every single tap).
- All timing uses the injected clock from core so tests are deterministic.

## Mapping persistence

- Stored as a JSON file in app support (`controls.json`), not in the song library. Controller setup is per-machine, not per-song.
- Schema versioned. Unknown commands are kept but marked inactive (forward compatibility with later phases).
- Per-song overrides: not built (decided). Bindings are global per machine.

## Feedback

- A small transient HUD in live mode shows the command that fired ("Next song"). Can be turned off.
- Settings show a live "last received" indicator for MIDI and keys, to debug a pedal without guessing.

## Test strategy

Integration-first; unit tests only for the tricky timing logic.

- **MIDI integration (primary):** create a real virtual CoreMIDI source with `MIDISourceCreateWithProtocol`, drive a running live-mode session with Note/CC/PC packets, and assert the live view actually changed (page, song, autoscroll state). Cover hot-plug by creating and disposing a source mid-test, and restart persistence of a learned binding via a real `controls.json`.
- **Key integration / E2E (XCUITest):** open a 3-song setlist in live mode, send preset keys with `typeKey`, assert page/song changes; focus the request-queue search field and assert pedal keys do not type into it.
- **Unit (narrow):** debounce and opt-in long-press state machine driven by the injected clock (tap, hold, bounce, interleaved bindings).
- **Manual E2E (recorded in the PR):** one real BT pedal in each preset mode and one USB MIDI controller through a 3-song setlist.

## Acceptance criteria

- With the "Arrows" preset, a paired BT pedal turns pages and changes songs in live mode with no settings changes.
- MIDI learn binds a foot-controller CC to "next song" in two clicks. The binding survives an app restart and controller unplug/replug.
- Pedal presses never type into a focused text field.
- A bouncy double-send within 150 ms fires once. With default presets every press fires instantly on keyDown; only a binding with an opt-in hold command waits for release, and holding it 600 ms fires the hold command and not the tap command.
- Bindings have no effect outside live mode.
- Works in the sandboxed App Store scheme with no extra permission prompts.
- Removing all controllers leaves live mode fully usable by keyboard/trackpad.

## Research items (verify at source before building)

- Whether a sandboxed macOS 26 app needs any entitlement for CoreMIDI input from USB, BLE and network sources.
- Bluetooth LE MIDI on macOS: is pairing only via Audio MIDI Setup, or is there an in-app API?
- Key codes actually sent by AirTurn (DUO/BT-200 modes) and PageFlip models in each mode, including whether any send media keys that a local monitor cannot see.
- Whether local `NSEvent` monitors receive events while a SwiftUI `TextField` is first responder, and the clean way to consume them.

## Resolved decisions

See `docs/decisions.md`.

1. **No MIDI output** - no program change / bank select on song change; the scope is input only.
2. **Live mode only** - the key monitor and MIDI command dispatch are active only while live mode is frontmost.
3. **No per-song overrides** - one global mapping per machine.
4. **Long-press opt-in** - presets fire on press; taps stay instant.

## Open questions

None new.
