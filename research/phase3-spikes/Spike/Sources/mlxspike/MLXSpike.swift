import Foundation
import FoundationModels
import MLX
import MLXGuidedGeneration
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import SpikeCore
import Tokenizers

// usage: mlxspike <modelDir> <modelName> paste|setreq <fixturesDir|-> <out.jsonl> [mode=hints|masked|plain] [split]

let args = CommandLine.arguments
func opt(_ name: String) -> String? {
    for a in args where a.hasPrefix(name + "=") { return String(a.dropFirst(name.count + 1)) }
    return nil
}

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

extension Duration {
    var ms: Double { Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15 }
}

struct Spec: @unchecked Sendable {
    let schema: String
    let system: String
}

/// Make every optional property explicit: type [T, "null"] and required, plus uniqueItems on arrays.
func nullable(_ json: String) -> String {
    guard var o = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          var props = o["properties"] as? [String: Any] else { return json }
    var req = Set(o["required"] as? [String] ?? [])
    for (k, v) in props {
        guard var p = v as? [String: Any] else { continue }
        if !req.contains(k), let t = p["type"] as? String { p["type"] = [t, "null"]; req.insert(k) }
        if (p["type"] as? String) == "array" { p["uniqueItems"] = true }
        props[k] = p
    }
    o["properties"] = props
    o["required"] = (o["x-order"] as? [String]) ?? Array(req)
    let d = try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    return String(decoding: d, as: UTF8.self)
}

func spec<T: Generable>(_ t: T.Type, instructions: String) -> Spec {
    var schema = schemaJSON(T.generationSchema)
    if CommandLine.arguments.contains("nullable") { schema = nullable(schema) }
    return Spec(
        schema: schema,
        system: instructions + "\n\nReply with only a JSON object that matches this JSON schema:\n" + schema)
}

@main
struct Main {
    static func main() async throws {
        let modelDir = URL(fileURLWithPath: args[1])
        let modelName = args[2]
        let task = args[3]
        let out = try JSONLWriter(path: args[5])
        let mode = Sheet.Mode(rawValue: opt("mode") ?? "hints") ?? .hints
        let split = args.contains("split")
        let thinkingOff: [String: any Sendable] = ["enable_thinking": false]

        Memory.peakMemory = 0
        let t0 = ContinuousClock.now
        let container = try await loadModelContainer(from: modelDir, using: #huggingFaceTokenizerLoader())
        let loadMs = (ContinuousClock.now - t0).ms
        print("loaded \(modelName) in \(Int(loadMs)) ms, footprint \(Int(footprintMB())) MB, mlx peak \(Memory.peakMemory / 1_048_576) MB")

        if let lim = opt("cachelimit").flatMap(Int.init) { Memory.cacheLimit = lim * 1_048_576 }
        let biasOn = args.contains("bias")
        let wsOnly = args.contains("wsbias")
        final class Partial: @unchecked Sendable { var text = "" }
        func run(_ sp: Spec, prompt: String, maxTokens: Int, rec: inout CallRecord) async {
            let partial = Partial()
            let system = sp.system
            let schema = sp.schema
            let start = ContinuousClock.now
            do {
                let (text, inTok, outTok) = try await container.perform { (context: ModelContext) -> (String, Int, Int) in
                    let tokenizer = context.tokenizer
                    let input = try await context.processor.prepare(
                        input: UserInput(chat: [.system(system), .user(prompt)], additionalContext: thinkingOff))
                    let gv = TokenizerVocabExtractor.extractForGrammar(from: tokenizer)
                    let gt = try GrammarTokenizer(
                        vocab: gv.vocab, vocabType: gv.vocabType, eosTokenId: Int32(tokenizer.eosTokenId ?? 0))
                    let constraint = try GrammarConstraint(
                        tokenizer: gt, jsonSchema: schema, fastForward: true, hostTokenizer: tokenizer)
                    var closing: MLXArray? = nil
                    var ws: MLXArray? = nil
                    var wsIDs = Set<Int>()
                    if biasOn {
                        closing = ClosingTokenBias.compute(tokenizer: tokenizer, eosTokenId: tokenizer.eosTokenId)
                        (ws, wsIDs) = WhitespaceTokenBias.compute(tokenizer: tokenizer)
                    }
                    if wsOnly { (ws, wsIDs) = WhitespaceTokenBias.compute(tokenizer: tokenizer) }
                    let n = try GuidedGenerationLoop.run(
                        input: input, context: context, constraint: constraint, maxTokens: maxTokens,
                        vocabSize: gt.vocabSize, closingBias: closing, whitespaceBias: ws,
                        whitespaceTokenIDs: wsIDs
                    ) { delta in
                        partial.text += delta
                        return true
                    }
                    return (partial.text, input.text.tokens.size, n)
                }
                rec.latencyMs = (ContinuousClock.now - start).ms
                rec.promptTokens = inTok
                rec.outputTokens = outTok
                // validate by decoding into the same Codable type the FM path uses
                rec.output = text
                rec.ok = true
            } catch {
                rec.latencyMs = (ContinuousClock.now - start).ms
                rec.errorKind = String(describing: type(of: error))
                rec.errorDetail = String(describing: error) + " partial=" + String(partial.text.suffix(300))
            }
            rec.peakMemoryMB = Double(Memory.peakMemory) / 1_048_576
        }

        func validate<T: Decodable>(_ t: T.Type, _ rec: inout CallRecord) {
            guard rec.ok, let o = rec.output else { return }
            if (try? JSONDecoder().decode(T.self, from: Data(o.utf8))) == nil {
                rec.ok = false
                rec.errorKind = "jsonDecode"
                rec.errorDetail = String(o.prefix(300))
            }
        }

        // warm-up: compile grammar + Metal kernels once (cold-start cost reported separately)
        do {
            var rec = CallRecord(runner: "mlx", model: modelName, task: "warmup", item: "warmup", variant: "")
            await run(spec(SongMetadata.self, instructions: Prompts.metadataInstructions),
                      prompt: "Top of the sheet:\nTest Song - Test Band\n\nChords in order: G C D", maxTokens: 60, rec: &rec)
            rec.errorDetail = (rec.errorDetail ?? "") + " loadMs=\(Int(loadMs)) footprintMB=\(Int(footprintMB()))"
            print("warmup", rec.ok, Int(rec.latencyMs), "ms", rec.output ?? rec.errorDetail ?? "")
            out.write(rec)
        }

        switch task {
        case "paste":
            let sheets = try loadSheets(dir: args[4])
            let only = opt("only")
            let variant = mode.rawValue + (split ? "-split" : "-combined") + (args.contains("exact") ? "-exact" : "")
            for s in sheets where only == nil || s.name.hasPrefix(only!) {
                var rec = CallRecord(runner: "mlx", model: modelName, task: "paste", item: s.name, variant: variant)
                let maxResp = (opt("maxbase").flatMap(Int.init) ?? 60) + 16 * s.blocks.count
                rec.chunks = split ? 2 : 1
                if split, args.contains("exact") {
                    var sp = spec(BlockLabelsOnly.self, instructions: Prompts.labelInstructions)
                    let fixed = sp.schema.replacingOccurrences(of: #""type":"array""#, with: #""type":"array","minItems":\#(s.blocks.count),"maxItems":\#(s.blocks.count)"#)
                        .replacingOccurrences(of: #""description":"Block number as shown in the sheet","type":"integer""#, with: #""description":"Block number as shown in the sheet","maximum":\#(s.blocks.count - 1),"minimum":0,"type":"integer""#)
                    sp = Spec(schema: fixed, system: sp.system.replacingOccurrences(of: sp.schema, with: fixed))
                    await run(sp, prompt: s.render(mode: mode), maxTokens: maxResp, rec: &rec)
                    validate(BlockLabelsOnly.self, &rec)
                } else if split {
                    await run(spec(BlockLabelsOnly.self, instructions: Prompts.labelInstructions),
                              prompt: s.render(mode: mode), maxTokens: maxResp, rec: &rec)
                    validate(BlockLabelsOnly.self, &rec)
                } else {
                    await run(spec(PasteEnrichment.self, instructions: Prompts.pasteInstructions),
                              prompt: s.render(mode: mode), maxTokens: maxResp, rec: &rec)
                    validate(PasteEnrichment.self, &rec)
                }
                print(s.name, rec.ok, rec.errorKind ?? "", Int(rec.latencyMs), "ms", rec.promptTokens ?? -1, "tok", rec.output ?? "")
                out.write(rec)
                if split {
                    var m = CallRecord(runner: "mlx", model: modelName, task: "paste", item: s.name, variant: variant)
                    m.chunk = 1
                    m.chunks = 2
                    if let mp = s.metadataPrompt() {
                        await run(spec(SongMetadata.self, instructions: Prompts.metadataInstructions),
                                  prompt: mp, maxTokens: 100, rec: &m)
                        validate(SongMetadata.self, &m)
                    } else {
                        m.ok = true
                        m.output = #"{"title":"","artist":"","key":"unknown","skipped":true}"#
                    }
                    print(s.name, "meta", m.ok, Int(m.latencyMs), "ms", m.output ?? m.errorDetail ?? "")
                    out.write(m)
                }
            }
        case "setreq":
            for (i, q) in Prompts.setRequests.enumerated() {
                var rec = CallRecord(runner: "mlx", model: modelName, task: "setreq", item: "S\(i + 1)", variant: args.contains("nullable") ? "nullable" : "cold")
                if args.contains("v3") {
                    rec.variant = "v3"
                    await run(spec(SetRequestV3.self, instructions: Prompts.setInstructionsV3), prompt: q, maxTokens: 150, rec: &rec)
                    validate(SetRequestV3.self, &rec)
                    if rec.ok, let o = rec.output { rec.output = Prompts.mergeV3(o, NumericRequest(q)) }
                } else if args.contains("v2") {
                    rec.variant = "v2"
                    await run(spec(SetRequestV2.self, instructions: Prompts.setInstructionsV2), prompt: q, maxTokens: 250, rec: &rec)
                    validate(SetRequestV2.self, &rec)
                } else {
                    await run(spec(SetRequestParse.self, instructions: Prompts.setInstructions), prompt: q, maxTokens: 250, rec: &rec)
                    validate(SetRequestParse.self, &rec)
                }
                print(rec.item, rec.ok, Int(rec.latencyMs), "ms", rec.output ?? rec.errorDetail ?? "")
                out.write(rec)
            }
        default:
            print("unknown task")
        }
        print("footprint now \(Int(footprintMB())) MB, mlx active \(Memory.activeMemory / 1_048_576) cache \(Memory.cacheMemory / 1_048_576)")
        print("final footprint \(Int(footprintMB())) MB, mlx peak \(Memory.peakMemory / 1_048_576) MB")
    }
}
