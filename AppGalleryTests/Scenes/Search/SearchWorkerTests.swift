import XCTest
@testable import AppGallery

@MainActor
final class SearchWorkerTests: XCTestCase {

    private func fixture(named name: String) throws -> Data {
        let bundle = Bundle(for: SearchWorkerTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makeWorker(statusCode: Int = 200, body: Data) -> SearchWorker {
        let session = StubURLProtocol.makeSession(statusCode: statusCode, body: body)
        return SearchWorker(apiClient: APIClient(session: session))
    }

    /// `search_response.json` is a real response of the API, trimmed to two applications.
    func testFetchAppsReturnsTheDecodedApplicationsInAPIOrder() async throws {
        let worker = makeWorker(body: try fixture(named: "search_response"))

        let apps = try await worker.fetchApps(matching: "spotify")

        XCTAssertEqual(apps.map(\.name), ["Spotify: Music and Podcasts", "YouTube"])
        XCTAssertEqual(apps.map(\.developer), ["Spotify", "Google"])
        XCTAssertEqual(apps.map(\.screenshotURLs.count), [8, 5])
    }

    func testFetchAppsRequestsTheSearchEndpointForTheTerm() async throws {
        let worker = makeWorker(body: Data(#"{"results": []}"#.utf8))

        _ = try await worker.fetchApps(matching: "spotify")

        let expectedURL = try ITunesEndpoint.search(term: "spotify").url
        XCTAssertEqual(StubURLProtocol.requests.map(\.url), [expectedURL])
    }

    func testFetchAppsPropagatesNetworkErrors() async {
        let worker = makeWorker(statusCode: 429, body: Data())

        await assertThrows(NetworkError.rateLimited) {
            try await worker.fetchApps(matching: "spotify")
        }
    }
}
