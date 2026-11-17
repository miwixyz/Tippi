import Foundation

/// The one session for requests to the cloud AI providers (audit 2026-11-17,
/// finding 9). `URLSession.shared` follows redirects and keeps the custom
/// key headers (`x-api-key`, `x-goog-api-key`) on the new request, and it
/// reads any answer to the end, however large.
///
/// - **No redirects.** The endpoints are fixed HTTPS URLs; a provider API
///   that suddenly redirects is broken or compromised, and the key must not
///   follow it to another host. The redirect response itself comes back as a
///   non-2xx status and surfaces as a normal HTTP error.
/// - **Ephemeral.** No cookies, no response cache on disk — the answers are
///   the user's rewritten text.
/// - **Size limit.** An answer above `maxResponseBytes` is rejected; a
///   streamed error body is cut at `maxErrorBodyBytes`.
enum ProviderSession {
    /// Far above any real completion (output is capped by max tokens).
    static let maxResponseBytes = 8 * 1024 * 1024
    static let maxErrorBodyBytes = 16 * 1024

    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config, delegate: RefuseProviderRedirects(), delegateQueue: nil)
    }()

    /// `data(for:)` with the size limit.
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await shared.data(for: request)
        try checkSize(data.count)
        return (data, response)
    }

    static func checkSize(_ count: Int) throws {
        guard count <= maxResponseBytes else { throw LLMError.invalidResponse }
    }

    /// Error body of a failed stream, at most `maxErrorBodyBytes`.
    static func errorBody(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var body = ""
        for try await line in bytes.lines {
            body += line
            if body.utf8.count >= maxErrorBodyBytes { break }
        }
        return body
    }
}

final class RefuseProviderRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
