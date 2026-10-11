import UttrflowPredict

/// Connects ordinary machine listings and alias metadata to the same local reader.
enum SuggestionEnvironmentIndex {
    static func make() -> EnvironmentIndex {
        let reader = SystemEnvironmentReader()
        return EnvironmentIndex(reader: reader, aliasReader: reader)
    }
}
