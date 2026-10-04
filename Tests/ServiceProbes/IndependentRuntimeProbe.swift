// Standalone offline native probe, intentionally outside the SwiftPM application target.
// See docs/independent-runtime.md for the exact compilation command.
import AppKit
import Foundation

private enum Fixture { case complete, incomplete, interrupted, cancelled }

private final class OfflineResponseProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var fixture: Fixture = .complete
    private static var requestCount = 0
    private static var stopCount = 0

    static func setFixture(_ fixture: Fixture) {
        lock.lock(); defer { lock.unlock() }
        self.fixture = fixture
    }

    static func counts() -> (requests: Int, stops: Int) {
        lock.lock(); defer { lock.unlock() }
        return (requestCount, stopCount)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixture
        Self.requestCount += 1
        Self.lock.unlock()
        // Every request is intercepted here. This class never opens a network connection.
        assert(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-only")
        if fixture == .cancelled { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream", "x-request-id": "fixture-request"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var payload = ": comment\n\ndata: {\"type\":\"response.created\",\"sequence_number\":0,\"response\":{\"id\":\"fixture-response\"}}\n\n"
        payload += "data: {\"type\":\"response.output_text.delta\",\"sequence_number\":1,\"delta\":\"Hi\"}\n\n"
        payload += "data: {\"type\":\"response.output_text.delta\",\"sequence_number\":1,\"delta\":\"Duplicate\"}\n\n"
        switch fixture {
        case .complete:
            payload += "data: {\"type\":\"response.completed\",\"sequence_number\":2,\"response\":{\"status\":\"completed\"}}\n\ndata: [DONE]\n\n"
        case .incomplete:
            payload += "data: {\"type\":\"response.incomplete\",\"sequence_number\":2}\n\n"
        case .interrupted, .cancelled: break
        }
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        Self.stopCount += 1
    }
}

private actor EventSink {
    var deltas = ""
    var responseID: String?
    func accept(_ event: IndependentStreamEvent) {
        switch event {
        case .delta(let value): deltas += value
        case .created(let value): responseID = value
        case .requestID: break
        }
    }
}

@main
struct IndependentRuntimeProbe {
    @MainActor
    static func main() async throws {
        var checks = [String]()
        var parser = ResponsesSSEParser()
        let comment = try parser.consume(line: ": keepalive")
        assert(comment == nil)
        let partial = try parser.consume(line: "data: {\"type\":")
        assert(partial == nil)
        let parsed = try parser.consume(line: "data: \"response.created\"}\r")
        assert(parsed?["type"] as? String == "response.created")
        checks.append("SSE split JSON, comments and CRLF")
        do {
            _ = try parser.consume(line: "data: " + String(repeating: "x", count: 1_048_577))
            fatalError("Oversized event accepted")
        } catch { checks.append("SSE oversized event refused") }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineResponseProtocol.self]
        let transport = ResponsesTextTransport(configuration: configuration)
        let sink = EventSink()
        OfflineResponseProtocol.setFixture(.complete)
        let output = try await transport.run(apiKey: "unit-test-only", model: "gpt-5-mini", messages: [],
                                             text: "Synthetic fixture", imageData: nil) { await sink.accept($0) }
        assert(output == "Hi")
        let deltas = await sink.deltas
        assert(deltas == "Hi")
        let responseID = await sink.responseID
        assert(responseID == "fixture-response")
        checks.append("Streaming deltas, response identity, duplicate sequence rejection and verified completion")

        for fixture in [Fixture.incomplete, .interrupted] {
            OfflineResponseProtocol.setFixture(fixture)
            do {
                _ = try await transport.run(apiKey: "unit-test-only", model: "gpt-5-mini", messages: [],
                                             text: "Synthetic fixture", imageData: nil) { _ in }
                fatalError("Non-completed stream was accepted")
            } catch { checks.append(fixture == .incomplete ? "Incomplete stream rejected" : "Disconnected stream rejected") }
        }

        OfflineResponseProtocol.setFixture(.cancelled)
        let cancellationTask = Task {
            try await transport.run(apiKey: "unit-test-only", model: "gpt-5-mini", messages: [],
                                    text: "Synthetic fixture", imageData: nil) { _ in }
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        let cancelledAt = ProcessInfo.processInfo.systemUptime
        cancellationTask.cancel()
        do { _ = try await cancellationTask.value; fatalError("Cancelled stream completed") }
        catch { checks.append("Cancellation ends owned pending HTTP transport") }
        let cancellationMilliseconds = (ProcessInfo.processInfo.systemUptime - cancelledAt) * 1000

        let adapter = IndependentAssistantAdapter()
        var disabledError: String?
        adapter.onError = { disabledError = $0 }
        await adapter.send(text: "This must not leave the machine.")
        assert(disabledError?.contains("disabled") == true)
        assert(!adapter.isActive && adapter.history.isEmpty)
        adapter.cancel()
        adapter.clearHistory()
        checks.append("Default-disabled adapter refuses send before Keychain or transport")
        let speech = SpeechOutputService()
        speech.speak(text: "")
        speech.stop()
        assert(!speech.isSpeaking)
        checks.append("Empty local speech creates no speaking state")

        let counts = OfflineResponseProtocol.counts()
        assert(counts.requests == 4)
        assert(counts.stops >= 1)
        let report: [String: Any] = ["checks": checks, "fixtureRequests": counts.requests,
                                    "networkRequests": 0, "cancellationMilliseconds": cancellationMilliseconds,
                                    "realAudioPlayed": false, "accountVerified": false]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
