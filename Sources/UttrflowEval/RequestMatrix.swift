// The classes of dictation that read like a request to the model, and how a model fails each one.
import UttrflowCore

/// One shape of dictation that reads as if it were addressed to the model.
public enum RequestClass: String, Sendable, Equatable, CaseIterable, Codable {
    case questions
    case assistantImperatives = "assistant-imperatives"
    case ignoreAndSystem = "ignore-and-system"
    case outputFormat = "output-format"
    case labelsAndQuotes = "labels-and-quotes"
    case politeRequests = "polite-requests"
    case hindiRequests = "hindi-requests"
    case shortInputs = "short-inputs"
    case refusalBait = "refusal-bait"
}

/// What a model does instead of tidying when it takes the dictation as a request.
public enum RequestFailure: String, Sendable, Equatable, CaseIterable, Codable {
    /// Does what the words ask.
    case obeyed
    /// Replies to the words as a question or a remark.
    case answered
    /// Writes the words in another language.
    case translated
    /// Adds a label, quotation or fence around the words, or strips one the speaker said.
    case wrapped
    /// Writes a refusal sentence in place of the words.
    case refused
}

/// One request-shaped dictation, with what a model that took it as a request would write.
public struct RequestCase: Sendable, Equatable {
    public let requestClass: RequestClass
    public let failure: RequestFailure
    /// The case scored like every other; its `expected` is the tidied dictation.
    public let evaluation: EvaluationCase
    /// The output of a fake model that commits `failure`, which the case's guards must catch.
    public let failed: String
}

/// How many request cases each class has, and whether that is enough.
public struct RequestMatrix: Sendable, Equatable {
    /// The fewest cases a class needs to count as measured.
    public static let measuredFloor = 8

    public let counts: [RequestClass: Int]

    public init(cases: [RequestCase] = EvaluationCorpus.requestCases) {
        counts = Dictionary(
            uniqueKeysWithValues: RequestClass.allCases.map { requestClass in
                (requestClass, cases.count { $0.requestClass == requestClass })
            })
    }

    /// The classes with fewer cases than the floor.
    public var underMeasured: [RequestClass] {
        RequestClass.allCases.filter { (counts[$0] ?? 0) < Self.measuredFloor }
    }
}

extension RequestClass {
    /// The class of the request case with this id, so a stored result is sliced by class without storing it.
    private static let byCaseID = Dictionary(
        uniqueKeysWithValues: EvaluationCorpus.requestCases.map { ($0.evaluation.id, $0.requestClass) })

    /// The class of the request case `caseID` names, or nil for a case outside the request corpus.
    public init?(caseID: String) {
        guard let requestClass = Self.byCaseID[caseID] else { return nil }
        self = requestClass
    }
}
