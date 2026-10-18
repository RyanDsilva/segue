import FoundationModels
let m = SystemLanguageModel.default
print("availability:", m.availability)
print("contextSize:", m.contextSize)
print("langs:", m.supportedLanguages.map{ $0.minimalIdentifier }.sorted())
