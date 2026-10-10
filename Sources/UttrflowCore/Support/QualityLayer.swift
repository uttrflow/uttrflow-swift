// The dictation-quality layers, each with a default state that a developer can override locally.

/// One switchable dictation-quality layer. See `Docs/dictation-quality.md`.
public enum QualityLayer: String, Sendable, CaseIterable {
    case recogniserBias = "recogniser-bias"
    case personaVocabulary = "persona-vocabulary"
    case evidenceCapture = "evidence-capture"
    case candidateGeneration = "candidate-generation"
    case scoring
    case overrideGate = "override-gate"
    case formatting

    /// Whether the layer runs when nothing overrides it; a new layer starts off until measured.
    public var defaultOn: Bool {
        switch self {
        case .recogniserBias, .evidenceCapture, .candidateGeneration, .scoring, .overrideGate, .formatting:
            true
        case .personaVocabulary: false
        }
    }

    /// The stage whose `StageTimeout` the layer runs inside.
    public var stageBudget: Duration {
        switch self {
        case .recogniserBias, .personaVocabulary, .evidenceCapture: StageTimeout.transcription
        case .candidateGeneration, .scoring, .overrideGate: StageTimeout.correction
        case .formatting: StageTimeout.transformation
        }
    }

    /// The layers whose output this one reads, so switching either off changes what this one is given.
    public var inputs: [QualityLayer] {
        switch self {
        case .personaVocabulary: []
        case .recogniserBias: [.personaVocabulary]
        case .evidenceCapture: [.recogniserBias]
        case .candidateGeneration: [.evidenceCapture]
        case .scoring: [.evidenceCapture, .candidateGeneration]
        case .overrideGate: [.candidateGeneration, .scoring]
        case .formatting: [.recogniserBias, .overrideGate]
        }
    }

    /// What the layer does, in one line, for Diagnostics and the bake-off header.
    public var summary: String {
        switch self {
        case .recogniserBias: "Conditions the recogniser on the user's own words."
        case .personaVocabulary: "Ranks those words by what this Mac recently saw the user keep."
        case .evidenceCapture: "Records what the recogniser can say about a doubtful word."
        case .candidateGeneration: "Proposes the words a doubtful run might have been."
        case .scoring: "Scores the heard reading against each candidate."
        case .overrideGate: "Lets a word move only when every condition holds."
        case .formatting: "Adds the punctuation, case and layout speech leaves implicit."
        }
    }

    /// The defaults key that overrides this layer; `-<key> NO` on the command line sets it for one launch.
    public var defaultsKey: String { "QualityLayer.\(rawValue)" }
}

/// Which quality layers are on, from their defaults and any local override, never from the network.
public struct QualityLayers: Sendable, Equatable {
    public let enabled: Set<QualityLayer>

    public init(enabled: Set<QualityLayer>) {
        self.enabled = enabled
    }

    /// Each layer's default, replaced by `override(defaultsKey)` where that returns a value.
    public init(override: (String) -> Bool? = { _ in nil }) {
        self.enabled = Set(QualityLayer.allCases.filter { override($0.defaultsKey) ?? $0.defaultOn })
    }

    /// The defaults with `only` (when given) as the whole set, then `without` removed; nil names an unknown layer.
    public static func ablation(only: String?, without: String?) -> QualityLayers? {
        guard let kept = only.map(parse) ?? Set(QualityLayer.allCases.filter(\.defaultOn)),
            let removed = without.map(parse) ?? []
        else { return nil }
        return QualityLayers(enabled: kept.subtracting(removed))
    }

    /// Each default-on layer switched off alone, then with each default-on layer it reads, in declaration order.
    public static var degradedPaths: [[QualityLayer]] {
        let defaults = QualityLayer.allCases.filter(\.defaultOn)
        let alone = defaults.map { [$0] }
        let pairs = defaults.flatMap { layer in
            layer.inputs.filter(\.defaultOn).map { input in defaults.filter { $0 == input || $0 == layer } }
        }
        return (alone + pairs).reduce(into: []) { paths, path in
            if !paths.contains(path) { paths.append(path) }
        }
    }

    /// Whether `layer` runs.
    public func isOn(_ layer: QualityLayer) -> Bool {
        enabled.contains(layer)
    }

    /// The enabled layers by name in declaration order, as a report header names them.
    public var names: [String] {
        QualityLayer.allCases.filter(enabled.contains).map(\.rawValue)
    }

    private static func parse(_ list: String) -> Set<QualityLayer>? {
        var layers = Set<QualityLayer>()
        for name in list.split(separator: ",") {
            guard let layer = QualityLayer(rawValue: String(name.filter { $0 != " " })) else { return nil }
            layers.insert(layer)
        }
        return layers
    }
}
