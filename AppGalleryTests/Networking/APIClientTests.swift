import os
import XCTest
@testable import AppGallery

final class APIClientTests: XCTestCase {

    private struct Payload: Decodable, Equatable, Sendable {
        let value: Int
    }

    private func makeRequest() throws -> URLRequest {
        URLRequest(url: try XCTUnwrap(URL(string: "https://example.com/payload")))
    }

    private func makeClient(statusCode: Int = 200, body: String) -> APIClient {
        APIClient(session: StubURLProtocol.makeSession(statusCode: statusCode, body: Data(body.utf8)))
    }

    // MARK: - Success

    func testSendDecodesTheBodyOfASuccessfulResponse() async throws {
        let client = makeClient(body: #"{"value": 42}"#)

        let payload: Payload = try await client.send(makeRequest())

        XCTAssertEqual(payload, Payload(value: 42))
    }

    // MARK: - HTTP status

    func testSendThrowsTheStatusCodeForANon2xxResponse() async throws {
        let client = makeClient(statusCode: 500, body: "{}")
        let request = try makeRequest()

        await assertThrows(NetworkError.http(statusCode: 500)) {
            let _: Payload = try await client.send(request)
        }
    }

    func testSendThrowsRateLimitedFor403And429() async throws {
        let request = try makeRequest()

        for statusCode in [403, 429] {
            let client = makeClient(statusCode: statusCode, body: "{}")

            await assertThrows(NetworkError.rateLimited) {
                let _: Payload = try await client.send(request)
            }
        }
    }

    // MARK: - Body

    func testSendThrowsDecodingForInvalidJSON() async throws {
        let client = makeClient(body: "not json")
        let request = try makeRequest()

        await assertThrows(NetworkError.decoding) {
            let _: Payload = try await client.send(request)
        }
    }

    // MARK: - Transport

    func testSendMapsAMissingConnectionToOffline() async throws {
        let client = APIClient(session: StubURLProtocol.makeSession(failingWith: URLError(.notConnectedToInternet)))
        let request = try makeRequest()

        await assertThrows(NetworkError.offline) {
            let _: Payload = try await client.send(request)
        }
    }

    func testSendMapsOtherTransportFailuresToTransport() async throws {
        let client = APIClient(session: StubURLProtocol.makeSession(failingWith: URLError(.timedOut)))
        let request = try makeRequest()

        await assertThrows(NetworkError.transport) {
            let _: Payload = try await client.send(request)
        }
    }

    func testSendMapsACancelledRequestToCancellationError() async throws {
        let client = APIClient(session: StubURLProtocol.makeSession(failingWith: URLError(.cancelled)))
        let request = try makeRequest()

        do {
            let _: Payload = try await client.send(request)
            XCTFail("Expected CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError, "Got \(error)")
        }
    }

    // MARK: - Cancellation

    /// The request is really in flight here: the protocol accepts it and never answers.
    /// Every wait has a timeout, so a broken cancellation fails this test instead of hanging it.
    func testCancellingTheCallingTaskCancelsTheRequestInFlight() async throws {
        let started = expectation(description: "URLSession started the request")
        let stopped = expectation(description: "URLSession withdrew the request")
        let returned = expectation(description: "send returned")
        let client = APIClient(session: HangingURLProtocol.makeSession(started: started, stopped: stopped))
        let request = try makeRequest()
        let thrownError = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)

        let call = Task {
            do {
                let _: Payload = try await client.send(request)
            } catch {
                thrownError.withLock { $0 = error }
            }
            returned.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)

        call.cancel()

        await fulfillment(of: [stopped, returned], timeout: 2)
        let error = thrownError.withLock { $0 }
        XCTAssertTrue(error is CancellationError, "Got \(String(describing: error))")
    }
}
