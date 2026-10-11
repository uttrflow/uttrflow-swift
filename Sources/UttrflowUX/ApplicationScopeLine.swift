// The one line an editor shows for where a snippet fires or a word is offered.
import UttrflowPredict

/// Where the draft applies, in one line: every app, or the apps the person chose, with ways to change it.
public struct ApplicationScopeLine: Sendable, Equatable {
    /// "Only in".
    public let label: String
    /// "Every app", or the chosen applications' names joined.
    public let summary: String
    /// Adds an application to the draft's list.
    public let choose: String
    /// Makes the draft apply everywhere again; absent when it already does.
    public let clear: String?

    /// The line for a draft confined to `applications`, empty meaning everywhere.
    public init(applications: [String]) {
        label = "Only in"
        summary =
            applications.isEmpty
            ? "Every app" : applications.map { SuggestionApplications.name(of: $0) }.joined(separator: ", ")
        choose = "Add App\u{2026}"
        clear = applications.isEmpty ? nil : "Every App"
    }
}
