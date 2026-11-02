#if os(macOS)
    import AudioToolbox
    import AVFoundation
    import CoreAudio
    import Foundation
    import Playback
    import Shows
    import Synchronization

    /// The one audio engine per process (P8-6 section 8.1): the rehearsal click's player and a
    /// bass and a chord sampler on one `AVAudioEngine`, so click and notes share one clock and
    /// one output device. Built lazily on the first sound, on its own serial queue; nothing
    /// here makes a sound until something is scheduled. While blocked (a gig is running) it
    /// holds no engine at all and drops everything scheduled.
    ///
    /// Notes reach the samplers sample-accurately and stay cancellable: each sampler keeps a
    /// queue of pending MIDI that a pre-render observer hands over in the render cycle each
    /// event falls in, stamped at its frame. (Events handed to a sampler ahead of time
    /// cannot be withdrawn: the P8-6a probe found reset and all-notes-off leave them
    /// sounding.)
    public final class AudioEngineHost: @unchecked Sendable {
        /// The process's engine (`AppDependencies.audio`, `LiveDependencies`' click).
        public static let shared = AudioEngineHost()

        /// Called once per launch, off the main thread, when the bundled bank fails to load
        /// and a fallback (the system bank, then the sampler's sine) is used.
        public var onBankFallback: (@Sendable () -> Void)?
        /// Called, off the main thread, when the output device or its format changed and the
        /// engine was torn down (it rebuilds on the next sound).
        public var onConfigurationChange: (@Sendable () -> Void)?

        private let blocked = Mutex(false)
        private let bankURL: URL?
        private let systemBankURL: URL?
        /// Offline manual rendering (the smoke test): renders on demand, never to a device.
        private let offline: Bool

        /// Everything below is touched only on `queue`.
        private let queue = DispatchQueue(
            label: uiString("dev.segue.audio-engine"),
            qos: .userInteractive,
        )
        private var engine: AVAudioEngine?
        private var player: AVAudioPlayerNode?
        private var bass: Sampler?
        private var chords: Sampler?
        private var ticks: [MetronomeAccent: AVAudioPCMBuffer] = [:]
        private var chordSound = ChordSound.piano
        private var bassSound = BassSound.finger
        private var volume: Float = 0.7
        /// The chosen output device's UID; nil = the system output.
        private var outputUID: String?
        private var configurationObserver: (any NSObjectProtocol)?
        private var reportedFallback = false

        static let offlineRate = 48000.0

        /// The engine on the bundled bank, falling back to the system bank.
        public convenience init() {
            self.init(bank: SoundBank.bundledURL, systemBank: SoundBank.systemURL)
        }

        init(bank: URL?, systemBank: URL?) {
            bankURL = bank
            systemBankURL = systemBank
            offline = false
        }

        /// An engine in offline manual rendering at 48 kHz stereo, for tests.
        init(offlineBank bank: URL?) {
            bankURL = bank
            systemBankURL = nil
            offline = true
        }

        // MARK: Blocking (section 9)

        public var isBlocked: Bool {
            blocked.withLock { $0 }
        }

        /// A gig is starting: everything stops and the engine and its nodes are released.
        /// Until `unblock()`, nothing builds and every schedule is dropped.
        public func block() {
            blocked.withLock { $0 = true }
            queue.sync { teardown() }
        }

        /// The gig ended. Nothing starts by itself.
        public func unblock() {
            blocked.withLock { $0 = false }
        }

        // MARK: Settings

        /// Which programs the samplers load (reloaded when the engine is running).
        public func setSounds(chord: ChordSound, bass: BassSound) {
            queue.async { [self] in
                let changed = chord != chordSound || bass != bassSound
                chordSound = chord
                bassSound = bass
                if changed, let bassSampler = self.bass, let chordSampler = chords {
                    loadPrograms(bass: bassSampler.unit, chords: chordSampler.unit)
                }
            }
        }

        /// The output level, 0 ... 1.
        public func setVolume(_ level: Float) {
            queue.async { [self] in
                volume = min(max(level, 0), 1)
                engine?.mainMixerNode.outputVolume = volume
            }
        }

        /// Where sound goes (Settings > Audio "Play through"): a device UID, or nil for the
        /// system output. A change tears a built engine down (the caller has stopped what was
        /// playing); the next sound builds it on the new device. A UID that is not connected
        /// plays through the system output.
        public func setOutputDevice(uid: String?) {
            queue.async { [self] in
                guard uid != outputUID else { return }
                outputUID = uid
                if engine != nil, !offline {
                    teardown()
                }
            }
        }

        /// Builds the engine and loads the bank without making a sound.
        public func prepare() {
            queue.async { [self] in
                _ = running()
            }
        }

        // MARK: Scheduling

        /// Plays `events` with onsets counted from `delay` seconds after now.
        func schedule(_ events: [NoteEvent], in delay: TimeInterval) {
            guard !isBlocked else { return }
            let base = offline ? nil : AVAudioTime.seconds(forHostTime: mach_absolute_time())
            queue.async { [self] in
                guard !isBlocked, running() != nil else { return }
                let start = (base ?? offlineNow()) + delay
                for event in events {
                    switch event.voice {
                    case .bass:
                        bass?.enqueue(event, at: start)
                    case .chord:
                        chords?.enqueue(event, at: start)
                    case let .click(accent):
                        scheduleTick(accent, at: start + event.onset)
                    }
                }
            }
        }

        /// One rehearsal click `delay` seconds from now.
        func scheduleClick(_ accent: MetronomeAccent, in delay: TimeInterval) {
            schedule(
                [NoteEvent(voice: .click(accent), note: 0, velocity: 100, onset: 0, duration: 0)],
                in: delay,
            )
        }

        /// Drops every pending note and releases the sounding ones.
        func stopNotes() {
            queue.async { [self] in
                bass?.cancelAll()
                chords?.cancelAll()
            }
        }

        /// Silences every click already scheduled.
        func stopClicks() {
            queue.async { [self] in
                player?.stop()
            }
        }

        // MARK: Engine

        private func offlineNow() -> TimeInterval {
            guard let engine else { return 0 }
            return Double(engine.manualRenderingSampleTime) / Self.offlineRate
        }

        /// The engine, built and running; nil while blocked or without a usable output.
        private func running() -> AVAudioEngine? {
            guard !isBlocked else { return nil }
            if engine == nil {
                build()
            }
            guard let engine else { return nil }
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    teardown()
                    return nil
                }
            }
            if let player, !player.isPlaying {
                player.play()
            }
            return engine
        }

        private func build() {
            let engine = AVAudioEngine()
            if !offline {
                route(engine)
            }
            let player = AVAudioPlayerNode()
            let bass = AVAudioUnitSampler()
            let chords = AVAudioUnitSampler()
            let submix = AVAudioMixerNode()
            let limiter = AVAudioUnitEffect(audioComponentDescription: Self.peakLimiter)
            guard let tickFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
            else { return }
            for node in [player, bass, chords, submix, limiter] as [AVAudioNode] {
                engine.attach(node)
            }
            engine.connect(player, to: submix, format: tickFormat)
            // `format: nil`: the mixer converts whatever rate the device runs at [A5].
            engine.connect(bass, to: submix, format: nil)
            engine.connect(chords, to: submix, format: nil)
            engine.connect(submix, to: limiter, format: nil)
            engine.connect(limiter, to: engine.mainMixerNode, format: nil)
            engine.mainMixerNode.outputVolume = volume
            if offline {
                guard let format = AVAudioFormat(
                    standardFormatWithSampleRate: Self.offlineRate,
                    channels: 2,
                ), (try? engine.enableManualRenderingMode(
                    .offline,
                    format: format,
                    maximumFrameCount: 512,
                )) != nil else { return }
            }
            ticks = [
                .downbeat: Self.tick(tickFormat, frequency: 1760, level: 0.9),
                .plain: Self.tick(tickFormat, frequency: 1320, level: 0.5),
            ].compactMapValues(\.self)
            self.engine = engine
            self.player = player
            loadPrograms(bass: bass, chords: chords)
            // The render observers go on after the banks are loaded.
            self.bass = Sampler(bass, offline: offline)
            self.chords = Sampler(chords, offline: offline)
            if !offline {
                configurationObserver = NotificationCenter.default.addObserver(
                    forName: .AVAudioEngineConfigurationChange,
                    object: engine,
                    queue: nil,
                ) { [weak self] _ in
                    self?.configurationChanged()
                }
            }
        }

        /// Points the output unit at the chosen device before anything is connected (so the
        /// main mixer takes that device's format); else it stays on the system output.
        private func route(_ engine: AVAudioEngine) {
            guard let outputUID,
                  var device = CoreAudioDevices.deviceID(forUID: outputUID),
                  let unit = engine.outputNode.audioUnit
            else { return }
            // A refusal (the device went away just now) leaves the system output.
            _ = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size),
            )
        }

        /// Apple's peak limiter, the safety net before the output.
        private static let peakLimiter = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0,
        )

        /// Loads the bass and chord programs: the bundled bank, else the system bank in
        /// place, else nothing (the sampler's sine).
        private func loadPrograms(bass: AVAudioUnitSampler, chords: AVAudioUnitSampler) {
            load(bass, program: SoundBank.program(bassSound), gain: SoundBank.gain(bassSound))
            load(chords, program: SoundBank.program(chordSound), gain: SoundBank.gain(chordSound))
        }

        private func load(_ unit: AVAudioUnitSampler, program: UInt8, gain: Float) {
            if load(unit, from: bankURL, program: program) {
                unit.overallGain = gain
                return
            }
            reportFallback()
            _ = load(unit, from: systemBankURL, program: program)
            unit.overallGain = 0
        }

        private func load(_ unit: AVAudioUnitSampler, from url: URL?, program: UInt8) -> Bool {
            guard let url, url.pathExtension.lowercased() != "sf3",
                  FileManager.default.fileExists(atPath: url.path)
            else { return false }
            do {
                try unit.loadSoundBankInstrument(
                    at: url,
                    program: program,
                    bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                    bankLSB: UInt8(kAUSampler_DefaultBankLSB),
                )
                return true
            } catch {
                return false
            }
        }

        private func reportFallback() {
            guard !reportedFallback else { return }
            reportedFallback = true
            onBankFallback?()
        }

        private func configurationChanged() {
            queue.async { [self] in
                teardown()
            }
            onConfigurationChange?()
        }

        private func teardown() {
            if let configurationObserver {
                NotificationCenter.default.removeObserver(configurationObserver)
            }
            configurationObserver = nil
            bass?.cancelAll()
            chords?.cancelAll()
            bass?.detach()
            chords?.detach()
            player?.stop()
            engine?.stop()
            engine = nil
            player = nil
            bass = nil
            chords = nil
        }

        private func scheduleTick(_ accent: MetronomeAccent, at seconds: TimeInterval) {
            guard let player, let buffer = ticks[accent] else { return }
            let when = if offline {
                AVAudioTime(
                    sampleTime: AVAudioFramePosition(seconds * buffer.format.sampleRate),
                    atRate: buffer.format.sampleRate,
                )
            } else {
                AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: seconds))
            }
            player.scheduleBuffer(buffer, at: when)
        }

        /// A 40 ms sine blip with a fast exponential decay (the rehearsal click, unchanged).
        private static func tick(
            _ format: AVAudioFormat,
            frequency: Double,
            level: Float,
        ) -> AVAudioPCMBuffer? {
            let frames = AVAudioFrameCount(format.sampleRate * 0.04)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = buffer.floatChannelData?[0]
            else { return nil }
            buffer.frameLength = frames
            for frame in 0 ..< Int(frames) {
                let time = Double(frame) / format.sampleRate
                let envelope = exp(-time / 0.008)
                samples[frame] = level * Float(sin(2 * .pi * frequency * time) * envelope)
            }
            return buffer
        }
    }

    /// Tests: the routed device, offline rendering, draining the queue.
    extension AudioEngineHost {
        /// The output device UID the next build routes to (tests).
        var routedOutputUID: String? {
            queue.sync { outputUID }
        }

        // MARK: Offline rendering (tests)

        /// Renders `seconds` of audio offline (left channel), after scheduling has been done.
        /// Only for an engine made with `init(offlineBank:)`.
        func renderOffline(seconds: TimeInterval) -> [Float] {
            queue.sync {
                guard offline, let engine = running(),
                      let buffer = AVAudioPCMBuffer(
                          pcmFormat: engine.manualRenderingFormat,
                          frameCapacity: engine.manualRenderingMaximumFrameCount,
                      )
                else { return [] }
                var samples: [Float] = []
                let total = Int(seconds * Self.offlineRate)
                while samples.count < total {
                    let frames = min(buffer.frameCapacity, AVAudioFrameCount(total - samples.count))
                    guard (try? engine.renderOffline(frames, to: buffer)) == .success,
                          let data = buffer.floatChannelData
                    else { break }
                    samples += UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength))
                }
                return samples
            }
        }

        /// Waits for everything queued so far (tests).
        func drain() {
            queue.sync {}
        }
    }
#endif
