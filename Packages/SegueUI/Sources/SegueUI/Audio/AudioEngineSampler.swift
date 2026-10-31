#if os(macOS)
    import AudioToolbox
    import AVFoundation
    import Foundation
    import Playback
    import Synchronization

    /// A sampler with its pending MIDI: note-ons and note-offs at absolute times (seconds on
    /// the host clock, or on the offline render's clock), handed to the unit by a pre-render
    /// observer in the cycle each falls in.
    final class Sampler: @unchecked Sendable {
        struct Pending {
            /// Seconds; `-infinity` = at the start of the next cycle.
            var time: Double
            var bytes: [UInt8]
        }

        /// The queue the render observer drains (its own object, so the observer never
        /// holds the sampler).
        final class Queue: Sendable {
            let items = Mutex<[Pending]>([])
        }

        let unit: AVAudioUnitSampler
        private let pending = Queue()
        private var token: Int?

        init(_ unit: AVAudioUnitSampler, offline: Bool) {
            self.unit = unit
            let audioUnit = unit.auAudioUnit
            let rate = unit.outputFormat(forBus: 0).sampleRate
            guard let send = audioUnit.scheduleMIDIEventBlock else { return }
            let pending = pending
            token = audioUnit.token { flags, timestamp, frames, _ in
                guard flags.contains(.unitRenderAction_PreRender) else { return }
                let stamp = timestamp.pointee
                let cycleStart: Double = if !offline,
                                            stamp.mFlags.contains(.hostTimeValid)
                {
                    AVAudioTime.seconds(forHostTime: stamp.mHostTime)
                } else {
                    stamp.mSampleTime / rate
                }
                let cycleEnd = cycleStart + Double(frames) / rate
                let due: [Pending] = pending.items.withLock { items in
                    guard items.contains(where: { $0.time < cycleEnd }) else { return [] }
                    let due = items.filter { $0.time < cycleEnd }
                    items.removeAll { $0.time < cycleEnd }
                    return due
                }
                for item in due {
                    var bytes = item.bytes
                    let offset = max(0, (item.time - cycleStart) * rate)
                    send(
                        AUEventSampleTime(stamp.mSampleTime + offset.rounded(.down)),
                        0,
                        bytes.count,
                        &bytes,
                    )
                }
            }
        }

        /// Queues `event`'s note-on and note-off, its onset counted from `start`.
        func enqueue(_ event: NoteEvent, at start: Double) {
            let on = start + event.onset
            pending.items.withLock { items in
                items.append(Pending(time: on, bytes: [0x90, event.note, event.velocity]))
                items.append(Pending(time: on + event.duration, bytes: [0x80, event.note, 0]))
                // A note-off and a re-strike of the same note at one instant: off first.
                items.sort { ($0.time, $0.bytes[0] & 0xF0 == 0x90 ? 1 : 0)
                    < ($1.time, $1.bytes[0] & 0xF0 == 0x90 ? 1 : 0)
                }
            }
        }

        /// Drops everything pending; the next cycle releases every sounding note.
        func cancelAll() {
            pending.items.withLock { items in
                items = [Pending(time: -.infinity, bytes: [0xB0, 123, 0])]
            }
        }

        func detach() {
            if let token {
                unit.auAudioUnit.removeRenderObserver(token)
            }
            token = nil
        }
    }
#endif
