import FoundationModels
import Foundation
let m = SystemLanguageModel.default
for i in 0..<3 {
  let s = LanguageModelSession(model: m)
  let t0 = ContinuousClock.now
  var first: Duration? = nil
  var last = ""
  for try await p in s.streamResponse(to: "Write the numbers from 1 to 60 separated by commas.", options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 200)) {
    if first == nil { first = ContinuousClock.now - t0 }
    last = p.content
  }
  let total = ContinuousClock.now - t0
  let n = try await m.tokenCount(for: Prompt(last))
  print("run", i, "ttft", first!, "total", total, "outTokens", n)
}
