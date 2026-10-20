import Foundation

/// The set assistant's tunable numbers (spec section 7: "weights in config"). The app reads
/// them from a bundled JSON file (`AIConfig/assistant.json`); `standard` is the default and
/// what a file leaves out keeps.
public struct AssistantConfig: Sendable, Hashable, Codable {
    public var schemaVersion: Int

    /// Each signal's weight: its contribution is `weight * raw value`.
    public var weights: Weights
    /// The raw proficiency value per level ("unset" for a song without one).
    public var proficiencyValues: ProficiencyValues
    /// Key-flow raw values between two neighbouring songs (summed, then weighted).
    public var flow: Flow
    /// Days for the recently-played penalty to halve (global across gigs, not venue-aware).
    public var recentHalfLifeDays: Double
    /// The duration window: target +/- this many seconds (spec: 3 min).
    public var toleranceSeconds: TimeInterval
    /// How much the seeded variety term may add (0 ... this) before weighting, so Rebuild
    /// can offer a different set of near-equal songs.
    public var varietySpread: Double
    /// Songs to pick when a request names neither a length nor a count and the setlist has
    /// no target length.
    public var fallbackSongCount: Int
    /// Local-swap passes over the order (key flow).
    public var swapPasses: Int

    public struct Weights: Sendable, Hashable, Codable {
        public var proficiency: Double
        public var tags: Double
        public var recent: Double
        public var slot: Double
        public var keyFlow: Double
        public var variety: Double

        public init(
            proficiency: Double = 1.0,
            tags: Double = 1.0,
            recent: Double = 0.8,
            slot: Double = 1.5,
            keyFlow: Double = 0.5,
            variety: Double = 1.0,
        ) {
            self.proficiency = proficiency
            self.tags = tags
            self.recent = recent
            self.slot = slot
            self.keyFlow = keyFlow
            self.variety = variety
        }
    }

    public struct ProficiencyValues: Sendable, Hashable, Codable {
        public var learning: Double
        public var unset: Double
        public var ready: Double
        public var pro: Double

        public init(
            learning: Double = 0,
            unset: Double = 0.3,
            ready: Double = 0.7,
            pro: Double = 1,
        ) {
            self.learning = learning
            self.unset = unset
            self.ready = ready
            self.pro = pro
        }
    }

    public struct Flow: Sendable, Hashable, Codable {
        /// The same key back to back.
        public var sameKey: Double
        /// Closely related keys (relative major/minor, a fifth apart, parallel).
        public var relatedKey: Double
        /// A capo change between neighbours.
        public var capoChange: Double
        /// A tuning change between neighbours.
        public var tuningChange: Double

        public init(
            sameKey: Double = -1.0,
            relatedKey: Double = 0.3,
            capoChange: Double = -0.5,
            tuningChange: Double = -1.0,
        ) {
            self.sameKey = sameKey
            self.relatedKey = relatedKey
            self.capoChange = capoChange
            self.tuningChange = tuningChange
        }
    }

    public init(
        weights: Weights = Weights(),
        proficiencyValues: ProficiencyValues = ProficiencyValues(),
        flow: Flow = Flow(),
        recentHalfLifeDays: Double = 30,
        toleranceSeconds: TimeInterval = 180,
        varietySpread: Double = 0.15,
        fallbackSongCount: Int = 10,
        swapPasses: Int = 3,
    ) {
        schemaVersion = 1
        self.weights = weights
        self.proficiencyValues = proficiencyValues
        self.flow = flow
        self.recentHalfLifeDays = recentHalfLifeDays
        self.toleranceSeconds = toleranceSeconds
        self.varietySpread = varietySpread
        self.fallbackSongCount = fallbackSongCount
        self.swapPasses = swapPasses
    }

    public static let standard = Self()

    /// Reads a config file; missing keys keep `standard`'s values.
    public static func decode(_ data: Data) throws -> Self {
        let file = try JSONDecoder().decode(File.self, from: data)
        var config = standard
        if let weights = file.weights {
            config.weights = weights
        }
        if let values = file.proficiencyValues {
            config.proficiencyValues = values
        }
        if let flow = file.flow {
            config.flow = flow
        }
        config.recentHalfLifeDays = file.recentHalfLifeDays ?? config.recentHalfLifeDays
        config.toleranceSeconds = file.toleranceSeconds ?? config.toleranceSeconds
        config.varietySpread = file.varietySpread ?? config.varietySpread
        config.fallbackSongCount = file.fallbackSongCount ?? config.fallbackSongCount
        config.swapPasses = file.swapPasses ?? config.swapPasses
        return config
    }

    private struct File: Decodable {
        var weights: Weights?
        var proficiencyValues: ProficiencyValues?
        var flow: Flow?
        var recentHalfLifeDays: Double?
        var toleranceSeconds: TimeInterval?
        var varietySpread: Double?
        var fallbackSongCount: Int?
        var swapPasses: Int?
    }
}
