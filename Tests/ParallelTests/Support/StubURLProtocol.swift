import Foundation

/// Inject this into `URLSessionConfiguration.protocolClasses` to handle
/// every request with a closure. Used by UpdateCheckerTests to avoid live
/// network in unit tests.
final class StubURLProtocol: URLProtocol {
    /// Replace per-test. Throwing → URLSession reports a failed request.
    /// Returning → response + body are delivered to the URLSession completion.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() { requestHandler = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "StubURLProtocol",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No handler set"]
            ))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Convenience: build a URLSession that routes through this stub.
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
