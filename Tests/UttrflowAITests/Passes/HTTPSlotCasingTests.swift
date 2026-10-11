import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("An HTTP method and a status reason phrase")
struct HTTPSlotCasingTests {
    private func spoken(_ text: String) -> String {
        CleaningPipeline.standard.run(Draft(text: text)).text
    }

    @Test(
        "a method before a path and a phrase after its code take their written case",
        arguments: [
            (
                "a post to slash api slash v two slash orders returns two oh one created",
                "A POST to /api/v2/orders returns 201 Created."
            ),
            (
                "the new endpoint is post slash api slash v two slash invoices",
                "The new endpoint is POST /api/v2/invoices."
            ),
            (
                "delete slash users slash twelve returns two oh four no content",
                "DELETE /users/12 returns 204 No Content."
            ),
            ("get slash api slash health returns two hundred ok", "GET /api/health returns 200 OK."),
            ("put slash users slash twelve returns two hundred ok", "PUT /users/12 returns 200 OK."),
            ("patch slash users slash twelve returns 422", "PATCH /users/12 returns 422."),
            ("head slash api slash health returns two hundred ok", "HEAD /api/health returns 200 OK."),
            ("the call returns four oh four not found", "The call returns 404 Not Found."),
            ("it came back four oh one unauthorized", "It came back 401 Unauthorized."),
            ("we saw five hundred internal server error", "We saw 500 Internal Server Error."),
            ("the proxy sent five oh two bad gateway", "The proxy sent 502 Bad Gateway."),
            ("the proxy sent five oh three service unavailable", "The proxy sent 503 Service Unavailable."),
            ("the proxy sent five oh four gateway timeout", "The proxy sent 504 Gateway Timeout."),
            ("the server replied four oh three forbidden", "The server replied 403 Forbidden."),
            ("the server replied four oh nine conflict", "The server replied 409 Conflict."),
            ("it redirects with three oh one moved permanently", "It redirects with 301 Moved Permanently."),
            ("it redirects with three oh two found", "It redirects with 302 Found."),
            ("the cache said three oh four not modified", "The cache said 304 Not Modified."),
            ("the limiter sent 429 too many requests", "The limiter sent 429 Too Many Requests."),
            ("the form got 400 bad request", "The form got 400 Bad Request."),
            ("send get to https://example.com/health", "Send GET to https://example.com/health."),
        ])
    func writesTheWrittenCase(input: String, expected: String) {
        #expect(spoken(input) == expected)
    }

    @Test(
        "an ordinary word with no path or code just before it keeps its case",
        arguments: [
            ("get the report", "Get the report."),
            ("post it", "Post it."),
            ("put the file in the folder", "Put the file in the folder."),
            ("delete this", "Delete this."),
            ("we got a four oh four in the logs", "We got a 404 in the logs."),
            ("we got a four oh four not enough time", "We got a 404 not enough time."),
            ("a get returns two hundred ok or four oh four", "A get returns 200 OK or 404."),
            ("the page is not found", "The page is not found."),
        ])
    func leavesOrdinaryWords(input: String, expected: String) {
        #expect(spoken(input) == expected)
    }

    @Test("the no content phrase is not read as a self-correction")
    func noContentIsNotACorrection() {
        let out = CleaningPipeline.standard.run(Draft(text: "it returns two oh four no content")).text
        #expect(out == "It returns 204 No Content.")
    }
}
