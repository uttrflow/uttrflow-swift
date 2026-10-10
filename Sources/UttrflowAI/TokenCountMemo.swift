// The token count of text that does not change between requests, counted once ahead of the request.

/// Remembers the count for the last text it counted, so a request for the same text pays nothing.
actor TokenCountMemo {
    /// The text last counted and its count.
    private var remembered: (text: String, tokens: Int)?

    /// The count for `text`, from memory when it matches the last one counted, else from `counting`.
    func tokens(
        for text: String, counting: @Sendable (String) async throws -> Int
    ) async throws -> Int {
        if let remembered, remembered.text == text { return remembered.tokens }
        let tokens = try await counting(text)
        remembered = (text, tokens)
        return tokens
    }
}
