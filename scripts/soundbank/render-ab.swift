#!/usr/bin/env swift
// Renders the sound bank listening A/B (P8-6 section 12 step 2): the same material from
// two SF2 banks, per voice, blind-labelled X and Y and loudness-matched per voice, so the
// choice is made by ear rather than by reputation or level.
//
// Usage: scripts/soundbank/render-ab.swift BANK_A.sf2 BANK_B.sf2 OUT_DIR [SEED]
//
// Writes OUT_DIR/<voice>-X.wav and <voice>-Y.wav for the voices finger bass (33), pick
// bass (34), piano (0), clean guitar (27) and a mix (finger bass + piano + click), and the
// blind key to OUT_DIR/key.txt. Renders offline (AVAudioEngine manual rendering), so it
// makes no sound and takes a second or two.

import AVFoundation
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write(Data("usage: render-ab.swift A.sf2 B.sf2 OUT_DIR [SEED]\n".utf8))
    exit(2)
}

let banks = [URL(fileURLWithPath: arguments[1]), URL(fileURLWithPath: arguments[2])]
let outDir = URL(fileURLWithPath: arguments[3], isDirectory: true)
var seed = UInt64(arguments.count > 4 ? arguments[4] : "") ?? UInt64(Date().timeIntervalSince1970)

let sampleRate = 44100.0
let tempo = 96.0
let beat = 60 / tempo
let melodicBankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)

struct Note {
    var sampler: Int // 0 bass, 1 chords
    var pitch: UInt8
    var velocity: UInt8
    var onset: Double
    var duration: Double
}

// MARK: Material

/// G - C - D - G at 96 BPM, one bar each, with two walk-ups (G to C: A B; D to G: E F#).
func bassLine() -> [Note] {
    let bars: [[UInt8]] = [[31, 31, 33, 35], [36, 36, 36, 36], [38, 38, 40, 42], [43]]
    var notes: [Note] = []
    for (bar, pitches) in bars.enumerated() {
        for (index, pitch) in pitches.enumerated() {
            let length = pitches.count == 1 ? 4 * beat : beat * 0.95
            notes.append(Note(
                sampler: 0,
                pitch: pitch,
                velocity: 96,
                onset: Double(bar * 4 + index) * beat,
                duration: length,
            ))
        }
    }
    return notes
}

/// G, C/G, D/F#, Em, Am7, D7, G, two beats each, the last held a bar.
let progressionPiano: [[UInt8]] = [
    [43, 55, 59, 62], [43, 55, 60, 64], [42, 54, 57, 62], [40, 55, 59, 64],
    [45, 55, 60, 64], [38, 54, 57, 60], [43, 55, 59, 62],
]
let progressionGuitar: [[UInt8]] = [
    [43, 47, 50, 55, 59, 67], [43, 48, 52, 55, 60, 64], [42, 50, 57, 62, 66],
    [40, 47, 52, 55, 59, 64], [45, 52, 55, 60, 64], [50, 57, 60, 66],
    [43, 47, 50, 55, 59, 67],
]

func progression(_ chords: [[UInt8]], strum: Double) -> [Note] {
    var notes: [Note] = []
    for (index, chord) in chords.enumerated() {
        let onset = Double(index * 2) * beat
        let last = index == chords.count - 1
        for (order, pitch) in chord.enumerated() {
            notes.append(Note(
                sampler: 1,
                pitch: pitch,
                velocity: 80,
                onset: onset + Double(order) * strum,
                duration: (last ? 4 : 2) * beat * 0.97,
            ))
        }
    }
    return notes
}

/// The mix: the bass line under G C D G on piano, one bar each, with a click.
func mixChords() -> [Note] {
    let chords: [[UInt8]] = [[55, 59, 62], [55, 60, 64], [54, 57, 62], [55, 59, 62]]
    return chords.enumerated().flatMap { bar, chord in
        chord.map { Note(
            sampler: 1,
            pitch: $0,
            velocity: 80,
            onset: Double(bar * 4) * beat,
            duration: 4 * beat * 0.97,
        ) }
    }
}

struct Voice {
    var name: String
    var bassProgram: UInt8?
    var chordProgram: UInt8?
    var notes: [Note]
    var click: Bool
}

let voices = [
    Voice(name: "bass-finger", bassProgram: 33, chordProgram: nil, notes: bassLine(), click: false),
    Voice(name: "bass-pick", bassProgram: 34, chordProgram: nil, notes: bassLine(), click: false),
    Voice(
        name: "piano",
        bassProgram: nil,
        chordProgram: 0,
        notes: progression(progressionPiano, strum: 0),
        click: false,
    ),
    Voice(
        name: "guitar",
        bassProgram: nil,
        chordProgram: 27,
        notes: progression(progressionGuitar, strum: 0.025),
        click: false,
    ),
    Voice(
        name: "mix",
        bassProgram: 33,
        chordProgram: 0,
        notes: bassLine() + mixChords(),
        click: true,
    ),
]

// MARK: Rendering

func render(_ voice: Voice, bank: URL) throws -> [[Float]] {
    let engine = AVAudioEngine()
    let samplers = [AVAudioUnitSampler(), AVAudioUnitSampler()]
    for sampler in samplers {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
        throw CocoaError(.featureUnsupported)
    }
    let chunk: AVAudioFrameCount = 32
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)
    if let program = voice.bassProgram {
        try samplers[0].loadSoundBankInstrument(
            at: bank,
            program: program,
            bankMSB: melodicBankMSB,
            bankLSB: 0,
        )
    }
    if let program = voice.chordProgram {
        try samplers[1].loadSoundBankInstrument(
            at: bank,
            program: program,
            bankMSB: melodicBankMSB,
            bankLSB: 0,
        )
    }
    try engine.start()
    defer { engine.stop() }

    struct Event { var frame: Int
        var on: Bool
        var note: Note
    }
    var events = voice.notes.flatMap {
        [
            Event(frame: Int($0.onset * sampleRate), on: true, note: $0),
            Event(frame: Int(($0.onset + $0.duration) * sampleRate), on: false, note: $0),
        ]
    }
    events.sort { ($0.frame, $0.on ? 1 : 0) < ($1.frame, $1.on ? 1 : 0) }
    let end = (voice.notes.map { $0.onset + $0.duration }.max() ?? 0) + 1.5
    let total = Int(end * sampleRate)
    var channels = [[Float]](repeating: [], count: 2)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
        throw CocoaError(.featureUnsupported)
    }
    var next = 0
    var frame = 0
    while frame < total {
        while next < events.count, events[next].frame <= frame {
            let event = events[next]
            let sampler = samplers[event.note.sampler]
            if event.on {
                sampler.startNote(event.note.pitch, withVelocity: event.note.velocity, onChannel: 0)
            } else {
                sampler.stopNote(event.note.pitch, onChannel: 0)
            }
            next += 1
        }
        let status = try engine.renderOffline(chunk, to: buffer)
        guard status == .success, let data = buffer.floatChannelData else { break }
        for channel in 0 ..< 2 {
            channels[channel].append(contentsOf: UnsafeBufferPointer(
                start: data[channel],
                count: Int(buffer
                    .frameLength),
            ))
        }
        frame += Int(buffer.frameLength)
    }
    return channels
}

/// The rehearsal click's tick (1760 Hz on beat 1, 1320 Hz otherwise), 40 ms.
func addClick(_ channels: inout [[Float]], bars: Int) {
    for index in 0 ..< bars * 4 {
        let start = Int(Double(index) * beat * sampleRate)
        let downbeat = index % 4 == 0
        let frequency = downbeat ? 1760.0 : 1320.0
        let level: Float = downbeat ? 0.25 : 0.15
        for frame in 0 ..< Int(0.04 * sampleRate) where start + frame < channels[0].count {
            let time = Double(frame) / sampleRate
            let value = level * Float(sin(2 * .pi * frequency * time) * exp(-time / 0.008))
            channels[0][start + frame] += value
            channels[1][start + frame] += value
        }
    }
}

func rms(_ channels: [[Float]]) -> Float {
    let squares = channels.flatMap(\.self).reduce(0.0) { $0 + Double($1) * Double($1) }
    return Float((squares / Double(max(1, channels[0].count * 2))).squareRoot())
}

func peak(_ channels: [[Float]]) -> Float {
    channels.flatMap(\.self).reduce(0) { max($0, abs($1)) }
}

func write(_ channels: [[Float]], gain: Float, to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
    ]
    let file = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false,
    )
    let count = channels[0].count
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(count),
    ),
        let data = buffer.floatChannelData
    else { throw CocoaError(.featureUnsupported) }
    buffer.frameLength = AVAudioFrameCount(count)
    for channel in 0 ..< 2 {
        for frame in 0 ..< count {
            data[channel][frame] = channels[channel][frame] * gain
        }
    }
    try file.write(from: buffer)
}

/// A small deterministic generator so a seed reproduces the blind labels.
func nextBit() -> Bool {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return (seed >> 33) & 1 == 1
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
var key = "Blind key for the sound bank A/B (do not open before listening)\n\n"
let targetRMS: Float = 0.08
for voice in voices {
    var renders = try banks.map { try render(voice, bank: $0) }
    if voice.click {
        for index in renders.indices {
            addClick(&renders[index], bars: 4)
        }
    }
    // Loudness match: the same RMS for both, then one shared trim so neither clips.
    var gains = renders.map { targetRMS / max(rms($0), 1e-6) }
    let loudest = zip(renders, gains).map { peak($0) * $1 }.max() ?? 1
    if loudest > 0.89 {
        gains = gains.map { $0 * 0.89 / loudest }
    }
    let swap = nextBit()
    let labels = swap ? ["Y", "X"] : ["X", "Y"]
    for (index, bank) in banks.enumerated() {
        let url = outDir.appendingPathComponent("\(voice.name)-\(labels[index]).wav")
        try write(renders[index], gain: gains[index], to: url)
        key += "\(voice.name)-\(labels[index]): \(bank.lastPathComponent)"
        key += String(
            format: " (raw peak %.2f, gain %.2f dB)\n",
            peak(renders[index]),
            20 * log10(gains[index]),
        )
    }
    print("rendered", voice.name)
}

try key.write(to: outDir.appendingPathComponent("key.txt"), atomically: true, encoding: .utf8)
