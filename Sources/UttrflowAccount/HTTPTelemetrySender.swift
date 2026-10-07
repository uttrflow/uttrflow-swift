// Posts telemetry reports to the backend's ingest endpoint.
public import struct Foundation.URL

/// Puts one report on the wire as `POST v1/telemetry`, signed in when a token is at hand. See Docs/account-telemetry.md.
public struct HTTPTelemetrySender: TelemetrySending {
    /// The API root, the same one `v1/me` is read from.
    private let baseURL: URL
    /// The only way this module reaches the network.
    private let transport: any BackendTransport
    /// The signed-in bearer token, or `nil` to send anonymously.
    private let bearer: @Sendable () async -> String?

    /// Sends through `transport` to `baseURL`, asking `bearer` for a token before each post.
    public init(
        baseURL: URL, transport: any BackendTransport,
        bearer: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.bearer = bearer
    }

    /// Posts the report's exact ingest bytes; no answer is ``TelemetryError/unreachable``, a non-2xx is a refusal.
    public func send(_ report: TelemetryReport) async throws(TelemetryError) {
        // A report that cannot be encoded is one the server would refuse, so it is refused here.
        guard let body = report.encodedForIngest() else { throw .refused(status: 400) }
        var headers = ["Content-Type": "application/json"]
        if let token = await bearer() { headers["Authorization"] = "Bearer \(token)" }
        let request = BackendRequest(
            method: .post, url: baseURL.appending(path: "v1/telemetry"), headers: headers, body: body,
            purpose: .usageStatistics)

        let response: BackendResponse
        do {
            response = try await transport.perform(request)
        } catch {
            throw .unreachable
        }
        guard response.isSuccess else { throw .refused(status: response.status) }
    }
}
