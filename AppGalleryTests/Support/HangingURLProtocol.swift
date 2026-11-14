import os
import XCTest

/// Accepts every request and never answers it, so a test can cancel a request that is really in flight.
/// `started` is fulfilled when `URLSession` hands the request over, `stopped` when it withdraws it.
final class HangingURLProtocol: URLProtocol {

    private struct Expectations {
        var started: XCTestExpectation?
        var stopped: XCTestExpectation?
    }

    /// `URLSession` calls the protocol on its own threads, so the shared state sits behind a lock.
    private static let expectations = OSAllocatedUnfairLock(initialState: Expectations())

    static func makeSession(started: XCTestExpectation, stopped: XCTestExpectation) -> URLSession {
        expectations.withLock { $0 = Expectations(started: started, stopped: stopped) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.expectations.withLock { $0.started }?.fulfill()
    }

    override func stopLoading() {
        Self.expectations.withLock { $0.stopped }?.fulfill()
    }
}
