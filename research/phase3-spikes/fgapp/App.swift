import AppKit
import FoundationModels

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 360, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "FM latency (foreground)"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await run() }
    }
    func run() async {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/fg.txt"
        var log = "frontmost=\(NSRunningApplication.current.isActive)\n"
        let m = SystemLanguageModel.default
        let sheets = (try? loadSheets(dir: CommandLine.arguments[2])) ?? []
        let s = sheets.first { $0.name.hasPrefix("E01") }!
        for i in 0..<6 {
            let t0 = ContinuousClock.now
            let sess = LanguageModelSession(model: m, instructions: Instructions(Prompts.metadataInstructions))
            _ = try? await sess.respond(to: s.metadataPrompt()!, generating: SongMetadata.self, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 80))
            let t1 = ContinuousClock.now
            let sess2 = LanguageModelSession(model: m, instructions: Instructions(Prompts.labelInstructions))
            _ = try? await sess2.respond(to: s.render(mode: .hints), schema: try! exactLabelsSchema(blocks: s.blocks.count), options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 200))
            let t2 = ContinuousClock.now
            let sess3 = LanguageModelSession(model: m, instructions: Instructions(Prompts.setInstructionsV3))
            _ = try? await sess3.respond(to: Prompts.setRequests[i], generating: SetRequestV3.self, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 80))
            let t3 = ContinuousClock.now
            log += "run \(i) active=\(NSRunningApplication.current.isActive) meta=\(t1 - t0) labels=\(t2 - t1) setreq=\(t3 - t2)\n"
        }
        try? log.write(toFile: out, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
@main
struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let d = Delegate()
        app.delegate = d
        app.setActivationPolicy(.regular)
        app.run()
    }
}
