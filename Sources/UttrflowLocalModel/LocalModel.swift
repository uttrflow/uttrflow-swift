public import UttrflowCore

// The open-weight models the bake-off measures, and how each one is described.
/// How a model's weights were compressed.
public enum Quantisation: String, Sendable, Equatable, Codable {
    /// Weights rounded to 4 bits after training.
    case fourBit = "4-bit"
    /// Trained with the rounding in the loop, which recovers some of what plain 4-bit rounding costs.
    case fourBitQAT = "4-bit QAT"
    /// Weights rounded to 8 bits after training.
    case eightBit = "8-bit"
    /// Weights as trained, in bfloat16.
    case unquantised = "bf16"
}

/// An open-weight model that runs on the user's Mac, with the real download size, not an estimate.
public struct LocalModel: Sendable, Hashable, Codable {
    /// Repository identifier.
    public let identifier: String
    /// Family, as its makers name it.
    public let family: String
    /// Release within that family.
    public let version: String
    /// Parameters before quantisation, in billions.
    public let parameterBillions: Double
    /// How its weights were compressed.
    public let quantisation: Quantisation
    /// What the download actually weighs.
    public let downloadBytes: Int64
    /// Whether it handles languages beyond English, which is why a local model is here at all.
    public let isMultilingual: Bool

    /// Records one candidate exactly as its repository describes it.
    public init(
        identifier: String,
        family: String,
        version: String,
        parameterBillions: Double,
        quantisation: Quantisation,
        downloadBytes: Int64,
        isMultilingual: Bool
    ) {
        self.identifier = identifier
        self.family = family
        self.version = version
        self.parameterBillions = parameterBillions
        self.quantisation = quantisation
        self.downloadBytes = downloadBytes
        self.isMultilingual = isMultilingual
    }

    /// A short name for reports and logs. Never shown to a user.
    public var shortName: String {
        identifier.split(separator: "/").last.map(String.init) ?? identifier
    }

    /// How the family and release read together, e.g. "Gemma 3".
    public var displayName: String { "\(family) \(version)" }

    /// Parameter count as people write it, e.g. "1B", "3.8B".
    public var parameterLabel: String {
        parameterBillions == parameterBillions.rounded()
            ? "\(Int(parameterBillions))B"
            : String(format: "%.1fB", parameterBillions)
    }

    /// Whether this model can be asked to work in `language`.
    public func supports(_ language: LanguageCode) -> Bool {
        isMultilingual || language == .english
    }
}

extension LocalModel {
    /// The candidates measured in the bake-off, smallest first. See `Docs/bakeoff-method.md`.
    public static let candidates: [LocalModel] = [
        gemma3Small, llama32, qwen3, ministral3, gemma3,
    ]

    /// Gemma 3 at 1B, the control: clean-up is a shallow task and this might be enough.
    public static let gemma3Small = LocalModel(
        identifier: "mlx-community/gemma-3-1b-it-qat-4bit",
        family: "Gemma", version: "3", parameterBillions: 1, quantisation: .fourBitQAT,
        downloadBytes: 770_000_000, isMultilingual: true
    )
    /// Llama 3.2 at 3B.
    public static let llama32 = LocalModel(
        identifier: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        family: "Llama", version: "3.2", parameterBillions: 3, quantisation: .fourBit,
        downloadBytes: 1_820_000_000, isMultilingual: true
    )
    /// Qwen 3 at 4B.
    public static let qwen3 = LocalModel(
        identifier: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
        family: "Qwen", version: "3 (2507)", parameterBillions: 4, quantisation: .fourBit,
        downloadBytes: 2_280_000_000, isMultilingual: true
    )
    /// Ministral 3 at 3B.
    public static let ministral3 = LocalModel(
        identifier: "mlx-community/Ministral-3-3B-Instruct-2512-4bit",
        family: "Ministral", version: "3 (2512)", parameterBillions: 3, quantisation: .fourBit,
        downloadBytes: 2_780_000_000, isMultilingual: true
    )
    /// Gemma 3 at 4B.
    public static let gemma3 = LocalModel(
        identifier: "mlx-community/gemma-3-4b-it-qat-4bit",
        family: "Gemma", version: "3", parameterBillions: 4, quantisation: .fourBitQAT,
        downloadBytes: 3_030_000_000, isMultilingual: true
    )

    /// The candidate that answers to `identifier`, by repository path or short name.
    public static func named(_ identifier: String) -> LocalModel? {
        candidates.first { $0.identifier == identifier || $0.shortName == identifier }
    }
}
