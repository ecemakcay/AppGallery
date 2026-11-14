import Foundation
import os

/// Answers every request of a `URLSession` from a closure, so networking tests never touch the network.
final class StubURLProtocol: URLProtocol {

    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private struct State {
        var handler: Handler?
        var requests: [URLRequest] = []
    }

    /// `URLSession` calls the protocol on its own threads, so the shared state sits behind a lock.
    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// The requests received since the last `makeSession` call, in order.
    static var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    /// A session whose requests are all answered by `handler`.
    static func makeSession(handler: @escaping Handler) -> URLSession {
        state.withLock { $0 = State(handler: handler) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A session that answers every request with the given status code and body.
    static func makeSession(statusCode: Int = 200, body: Data) -> URLSession {
        makeSession { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badURL)
            }
            return (response, body)
        }
    }

    /// A session whose every request fails with `error`.
    static func makeSession(failingWith error: URLError) -> URLSession {
        makeSession { _ in throw error }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let request = request
        let handler = Self.state.withLock { state in
            state.requests.append(request)
            return state.handler
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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
}
