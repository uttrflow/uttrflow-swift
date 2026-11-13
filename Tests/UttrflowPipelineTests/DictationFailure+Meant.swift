// The failure a pipeline test expects, carrying the application its fake context reads.
import UttrflowCore

@testable import UttrflowPipeline
@testable import UttrflowTestSupport

extension DictationFailure {
    /// This failure as the pipeline ends it after reading `context`, naming the app the words were for.
    func meant(for context: AppContext = .fixture()) -> DictationFailure {
        markingDestination(context.bundleIdentifier)
    }
}
