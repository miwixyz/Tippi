import XCTest
@testable import Tippi

/// gpt-6 Sol/Luna think at "medium" on every call unless the request carries
/// `reasoning_effort: "none"` — and with any other effort OpenAI rejects
/// `temperature` with HTTP 400 (latest-model guide, checked 2026-09-25).
/// These tests pin both halves: which models get the switch-off, and that the
/// field really lands in the JSON body.
final class ReasoningEffortTests: XCTestCase {

    func testGpt6LunaAndSolRunWithoutReasoningAndKeepTemperature() {
        let openAI = OpenAIProvider()
        for model in ["gpt-6-luna", "gpt-6-sol"] {
            XCTAssertEqual(openAI.reasoningEffort(for: model), "none", model)
            XCTAssertEqual(openAI.temperature(for: model), 0.3, model)
        }
    }

    /// Astra does not support "none" — it must keep its default effort, and
    /// then temperature has to be omitted or the request 400s.
    func testGpt6AstraKeepsReasoningAndDropsTemperature() {
        let openAI = OpenAIProvider()
        XCTAssertNil(openAI.reasoningEffort(for: "gpt-6-astra"))
        XCTAssertNil(openAI.temperature(for: "gpt-6-astra"))
    }

    func testOlderModelsAreUnchanged() {
        let openAI = OpenAIProvider()
        XCTAssertNil(openAI.reasoningEffort(for: "gpt-5.6-terra"))
        XCTAssertNil(openAI.temperature(for: "gpt-5.6-terra"))
    }

    func testOpenRouterSwitchesOffOnlyForGpt6LunaAndSol() {
        let router = OpenRouterProvider()
        XCTAssertEqual(router.reasoningEffort(for: "openai/gpt-6-luna"), "none")
        XCTAssertEqual(router.reasoningEffort(for: "openai/gpt-6-sol"), "none")
        XCTAssertNil(router.reasoningEffort(for: "openai/gpt-6-astra"))
        XCTAssertNil(router.reasoningEffort(for: "anthropic/claude-haiku-4.5"))
    }

    func testNonOpenAIProvidersSendNoReasoningEffort() {
        XCTAssertNil(GroqProvider().reasoningEffort(for: "openai/gpt-oss-20b"))
    }

    // MARK: - The field actually reaches the wire

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(BodyCapture.self)
        BodyCapture.lastBody = nil
    }

    override func tearDown() {
        URLProtocol.unregisterClass(BodyCapture.self)
        super.tearDown()
    }

    func testRequestBodyCarriesReasoningEffortWhenSet() async throws {
        _ = try await openAIChatComplete(
            endpoint: URL(string: "https://capture.invalid/v1/chat/completions")!,
            apiKey: "test", model: "gpt-6-luna",
            systemPrompt: "s", userText: "u",
            temperature: 0.3, reasoningEffort: "none")
        let json = try XCTUnwrap(BodyCapture.lastJSON())
        XCTAssertEqual(json["reasoning_effort"] as? String, "none")
        XCTAssertEqual(json["temperature"] as? Double, 0.3)
    }

    func testRequestBodyOmitsReasoningEffortWhenNil() async throws {
        _ = try await openAIChatComplete(
            endpoint: URL(string: "https://capture.invalid/v1/chat/completions")!,
            apiKey: "test", model: "mistral-small-latest",
            systemPrompt: "s", userText: "u",
            temperature: 0.3)
        let json = try XCTUnwrap(BodyCapture.lastJSON())
        XCTAssertNil(json["reasoning_effort"])
    }
}

/// Answers every request with a minimal chat-completion and keeps the body.
private final class BodyCapture: URLProtocol {
    nonisolated(unsafe) static var lastBody: Data?

    static func lastJSON() -> [String: Any]? {
        guard let lastBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: lastBody)) as? [String: Any]
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "capture.invalid"
    }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let payload = #"{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
