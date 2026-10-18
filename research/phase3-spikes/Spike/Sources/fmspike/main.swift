import Foundation
import FoundationModels
import SpikeCore

let args = CommandLine.arguments
let model = SystemLanguageModel.default

func errorKind(_ e: Error) -> (String, String) {
    if let g = e as? LanguageModelSession.GenerationError {
        let kind: String
        switch g {
        case .exceededContextWindowSize: kind = "exceededContextWindowSize"
        case .assetsUnavailable: kind = "assetsUnavailable"
        case .guardrailViolation: kind = "guardrailViolation"
        case .unsupportedGuide: kind = "unsupportedGuide"
        case .unsupportedLanguageOrLocale: kind = "unsupportedLanguageOrLocale"
        case .decodingFailure: kind = "decodingFailure"
        case .rateLimited: kind = "rateLimited"
        case .concurrentRequests: kind = "concurrentRequests"
        case .refusal: kind = "refusal"
        @unknown default: kind = "unknownGenerationError"
        }
        return (kind, String(describing: g))
    }
    return ("other", String(describing: e))
}

func opt(_ name: String) -> String? {
    for a in args where a.hasPrefix(name + "=") { return String(a.dropFirst(name.count + 1)) }
    return nil
}

func call<T: Generable & Encodable>(
    _ type: T.Type, instructions: String, prompt: String, maxTokens: Int,
    record: inout CallRecord
) async {
    let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
    record.contextSize = model.contextSize
    record.instructionTokens = try? await model.tokenCount(for: Instructions(instructions))
    record.schemaTokens = try? await model.tokenCount(for: T.generationSchema)
    record.promptTokens = try? await model.tokenCount(for: Prompt(prompt))
    let start = ContinuousClock.now
    do {
        let r = try await session.respond(
            to: prompt, generating: T.self, includeSchemaInPrompt: true,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens))
        record.latencyMs = (ContinuousClock.now - start).ms
        record.ok = true
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        record.output = String(data: try enc.encode(r.content), encoding: .utf8)
        record.outputTokens = try? await model.tokenCount(for: Prompt(r.rawContent.jsonString))
        record.transcriptTokens = try? await model.tokenCount(for: session.transcript)
    } catch {
        record.latencyMs = (ContinuousClock.now - start).ms
        let (k, d) = errorKind(error)
        record.errorKind = k
        record.errorDetail = d
        record.transcriptTokens = try? await model.tokenCount(for: session.transcript)
    }
}

func callSchema(_ schema: GenerationSchema, instructions: String, prompt: String, maxTokens: Int, record: inout CallRecord) async {
    let session = LanguageModelSession(model: model, instructions: Instructions(instructions))
    record.contextSize = model.contextSize
    record.instructionTokens = try? await model.tokenCount(for: Instructions(instructions))
    record.schemaTokens = try? await model.tokenCount(for: schema)
    record.promptTokens = try? await model.tokenCount(for: Prompt(prompt))
    let start = ContinuousClock.now
    do {
        let r = try await session.respond(to: prompt, schema: schema, includeSchemaInPrompt: true,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens))
        record.latencyMs = (ContinuousClock.now - start).ms
        record.ok = true
        record.output = r.content.jsonString
        record.outputTokens = try? await model.tokenCount(for: Prompt(r.content.jsonString))
    } catch {
        record.latencyMs = (ContinuousClock.now - start).ms
        let (k, d) = errorKind(error)
        record.errorKind = k
        record.errorDetail = d
    }
}

extension Duration {
    var ms: Double { Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15 }
}

@main
struct Main {
    static func main() async throws {
        print("availability:", model.availability, "contextSize:", model.contextSize)
        guard case .available = model.availability else { exit(2) }
        let cmd = args.count > 1 ? args[1] : "help"
        if cmd == "numparse" {
            for q in Prompts.setRequests { let n = NumericRequest(q); print(q, "=>", n.minutes, n.songCount, n.minBPM, n.maxBPM, n.keys) }
            return
        }
        switch cmd {
        case "dump":
            for s in try loadSheets(dir: args[2]) {
                print("=== \(s.name) blocks=\(s.blocks.count)")
                for b in s.blocks { print("  [\(b.index)] \(b.hint ?? "-") | \(b.lines.first ?? "")") }
            }
            var hints: [String: [String]] = [:]
            for s in try loadSheets(dir: args[2]) { hints[s.name] = s.blocks.map { $0.hint ?? "" } }
            try JSONEncoder().encode(hints).write(to: URL(fileURLWithPath: "hints.json"))
            for s in try loadSheets(dir: args[2]).prefix(1) {
                print(s.render(mode: .hints)); print(s.render(mode: .masked)); print(s.metadataPrompt() ?? "nil")
            }
            print(schemaJSON(PasteEnrichment.generationSchema))
            print(schemaJSON(SetRequestParse.generationSchema))
        case "paste":
            let sheets = try loadSheets(dir: args[2])
            let out = try JSONLWriter(path: args[3])
            let mode = Sheet.Mode(rawValue: opt("mode") ?? "hints") ?? .hints
            let split = args.contains("split")
            let forcedBudget = opt("budget").flatMap(Int.init)
            let repeats = opt("repeat").flatMap(Int.init) ?? 1
            let only = opt("only")
            let variant = mode.rawValue + (split ? "-split" : "-combined") + (args.contains("exact") ? "-exact" : "") + (forcedBudget.map { "-budget\($0)" } ?? "")
            let instr = split ? Prompts.labelInstructions : Prompts.pasteInstructions
            let instrTok = try await model.tokenCount(for: Instructions(instr))
            let schemaTok = try await model.tokenCount(for: split ? BlockLabelsOnly.generationSchema : PasteEnrichment.generationSchema)
            for _ in 0..<repeats {
                for s in sheets where only == nil || s.name.hasPrefix(only!) {
                    let full = s.render(mode: mode)
                    let fullTok = try await model.tokenCount(for: Prompt(full))
                    let maxResp = 40 + 14 * s.blocks.count
                    let budget = forcedBudget ?? (model.contextSize - instrTok - schemaTok - maxResp - 150)
                    var chunks: [ArraySlice<Sheet.Block>] = []
                    if fullTok <= budget {
                        chunks = [s.blocks[...]]
                    } else {
                        var start = 0
                        var end = 0
                        while start < s.blocks.count {
                            end = start + 1
                            while end < s.blocks.count {
                                let t = try await model.tokenCount(
                                    for: Prompt(s.render(blocks: s.blocks[start...end], mode: mode)))
                                if t > budget { break }
                                end += 1
                            }
                            chunks.append(s.blocks[start..<end])
                            start = end
                        }
                    }
                    for (ci, ch) in chunks.enumerated() {
                        var rec = CallRecord(runner: "fm", model: "apple-fm", task: "paste", item: s.name, variant: variant)
                        rec.chunk = ci
                        rec.chunks = chunks.count + (split ? 1 : 0)
                        let prompt = chunks.count == 1 ? full : s.render(blocks: ch, mode: mode)
                        if split, args.contains("exact") {
                            await callSchema(try exactLabelsSchema(blocks: ch.count), instructions: Prompts.labelInstructions,
                                             prompt: prompt, maxTokens: maxResp, record: &rec)
                        } else if split {
                            await call(BlockLabelsOnly.self, instructions: Prompts.labelInstructions,
                                       prompt: prompt, maxTokens: maxResp, record: &rec)
                        } else if ci == 0 {
                            await call(PasteEnrichment.self, instructions: Prompts.pasteInstructions,
                                       prompt: prompt, maxTokens: maxResp, record: &rec)
                        } else {
                            await call(BlockLabelsOnly.self, instructions: Prompts.chunkInstructions,
                                       prompt: prompt, maxTokens: maxResp, record: &rec)
                        }
                        print(s.name, ci, rec.ok, rec.errorKind ?? "", Int(rec.latencyMs), "ms", rec.promptTokens ?? -1, "tok")
                        out.write(rec)
                    }
                    if split {
                        var rec = CallRecord(runner: "fm", model: "apple-fm", task: "paste", item: s.name, variant: variant)
                        rec.chunk = chunks.count
                        rec.chunks = chunks.count + 1
                        if let mp = s.metadataPrompt() {
                            await call(SongMetadata.self, instructions: Prompts.metadataInstructions,
                                       prompt: mp, maxTokens: 80, record: &rec)
                        } else {
                            rec.ok = true
                            rec.output = #"{"title":"","artist":"","key":"unknown","skipped":true}"#
                        }
                        print(s.name, "meta", rec.ok, rec.errorKind ?? "", Int(rec.latencyMs), "ms", rec.output ?? "")
                        out.write(rec)
                    }
                }
            }
        case "setreq":
            let out = try JSONLWriter(path: args[2])
            let repeats = opt("repeat").flatMap(Int.init) ?? 1
            let prewarm = args.contains("prewarm")
            for _ in 0..<repeats {
                for (i, q) in Prompts.setRequests.enumerated() {
                    var rec = CallRecord(runner: "fm", model: "apple-fm", task: "setreq", item: "S\(i + 1)", variant: prewarm ? "prewarm" : "cold")
                    if prewarm {
                        // what the app would do when the pick field gets focus
                        let s = LanguageModelSession(model: model, instructions: Instructions(args.contains("v3") ? Prompts.setInstructionsV3 : args.contains("v2") ? Prompts.setInstructionsV2 : Prompts.setInstructions))
                        s.prewarm()
                        try await Task.sleep(for: .seconds(1.5))
                    }
                    if args.contains("v3") {
                        rec.variant += "-v3"
                        await call(SetRequestV3.self, instructions: Prompts.setInstructionsV3, prompt: q, maxTokens: 80, record: &rec)
                        if rec.ok, let o = rec.output { rec.output = Prompts.mergeV3(o, NumericRequest(q)) }
                    } else if args.contains("v2") {
                        rec.variant += "-v2"
                        await call(SetRequestV2.self, instructions: Prompts.setInstructionsV2, prompt: q, maxTokens: 150, record: &rec)
                    } else {
                        await call(SetRequestParse.self, instructions: Prompts.setInstructions, prompt: q, maxTokens: 200, record: &rec)
                    }
                    print(rec.item, rec.ok, rec.errorKind ?? "", Int(rec.latencyMs), "ms", rec.output ?? "")
                    out.write(rec)
                }
            }
        case "probe":
            // language-check probes: Hinglish-only prompt, instructions in English
            let probes = [
                ("hinglish-lyrics-only", "Main chup hoon, bas dekhta hoon\nTeri aankhon mein sapne kaise\nDil ki baatein, dil hi jaane"),
                ("devanagari", "मैं चुप हूँ, बस देखता हूँ\nतेरी आँखों में सपने कैसे"),
                ("english", "Paper lanterns on the water\nFloating where the river bends"),
            ]
            let out = try JSONLWriter(path: args[2])
            for (name, text) in probes + [("masked-H07", Sheet(name: "x", raw: "Tum ho toh subah hai\nTum ho toh shaam\n\nNa chaand chahiye\nBas tum raho").render(mode: .masked))] {
                var rec = CallRecord(runner: "fm", model: "apple-fm", task: "probe", item: name, variant: "labels")
                await call(BlockLabelsOnly.self, instructions: Prompts.chunkInstructions,
                           prompt: name.hasPrefix("masked") ? text : "Block 0:\n" + text, maxTokens: 60, record: &rec)
                print(name, rec.ok, rec.errorKind ?? "", rec.errorDetail ?? "", rec.output ?? "")
                out.write(rec)
            }
        default:
            print("usage: fmspike dump|paste|setreq|probe ...")
        }
    }
}
