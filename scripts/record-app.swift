#!/usr/bin/env swift
// Records one app's windows in a screen rectangle with ScreenCaptureKit, for the guide clips
// (make docs-clips) and the App Store preview (make preview).
//
//   scripts/record-app.swift <out.mov> <bundle id> <x,y,w,h points, top-left of the main
//       screen> <cursor 0|1> <started file>
//
// Waits for the app to put a window on screen, then records only that app's windows (sheets,
// popovers, menus and the stage included): no other app, no wallpaper, and no system overlay
// such as XCUITest's "Automation Running" banner, all of which a plain screen recording
// picked up. Writes the first frame's wall-clock time (epoch seconds) to <started file>, so
// the clip markers cut the recording exactly. Stops cleanly on SIGINT or SIGTERM, or after
// 120 s. Needs Screen Recording permission for the terminal ([RYAN], once).

import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("record-app: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 6 else {
    fail("usage: record-app.swift <out.mov> <bundle id> <x,y,w,h> <cursor 0|1> <started file>")
}

let output = URL(fileURLWithPath: arguments[1])
let bundleID = arguments[2]
let numbers = arguments[3].split(separator: ",").compactMap { Double($0) }
guard numbers.count == 4 else { fail("bad rect \(arguments[3])") }
let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
let showsCursor = arguments[4] == "1"
let startedFile = URL(fileURLWithPath: arguments[5])

final class Recorder: NSObject, SCStreamOutput, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    var started = false
    let queue = DispatchQueue(label: "record-app")

    init(width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: output)
        writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 40_000_000],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }

    func stream(
        _: SCStream,
        didOutputSampleBuffer buffer: CMSampleBuffer,
        of type: SCStreamOutputType,
    ) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                  buffer,
                  createIfNecessary: false,
              )
              as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: status) == .complete
        else { return }
        if !started {
            started = true
            writer.startWriting()
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            let now = String(format: "%.3f", Date().timeIntervalSince1970)
            try? now.write(to: startedFile, atomically: true, encoding: .utf8)
        }
        if input.isReadyForMoreMediaData {
            input.append(buffer)
        }
    }

    func finish() async {
        guard started else { return }
        input.markAsFinished()
        await writer.finishWriting()
    }
}

/// The app's running entry once it has a window on screen (polls, up to 60 s).
func waitForApp() async throws -> (SCShareableContent, SCRunningApplication) {
    for _ in 0 ..< 300 {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true,
        )
        if let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }),
           content.windows.contains(where: { $0.owningApplication?.processID == app.processID })
        {
            return (content, app)
        }
        try await Task.sleep(for: .milliseconds(200))
    }
    fail("\(bundleID) never showed a window")
}

let semaphore = DispatchSemaphore(value: 0)
var stopRequested = false
for signalNumber in [SIGINT, SIGTERM] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler { stopRequested = true }
    source.resume()
    _ = Unmanaged.passRetained(source)
}

Task {
    do {
        let (content, app) = try await waitForApp()
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
        else { fail("no main display") }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let scale = Double(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = showsCursor
        configuration.backgroundColor = .black
        configuration.queueDepth = 8
        let recorder = try Recorder(width: configuration.width, height: configuration.height)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.queue)
        try await stream.startCapture()
        let deadline = Date().addingTimeInterval(120)
        while !stopRequested, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await stream.stopCapture()
        await recorder.finish()
        semaphore.signal()
    } catch {
        fail("\(error)")
    }
}

while semaphore.wait(timeout: .now()) == .timedOut {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
