import XCTest
@testable import AppGallery

final class ITunesEndpointTests: XCTestCase {

    private func queryItems(of request: URLRequest) throws -> [String: String] {
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testSearchTargetsTheITunesSearchEndpoint() throws {
        let url = try XCTUnwrap(ITunesEndpoint.search(term: "spotify").url)

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertEqual(url.path, "/search")
    }

    func testSearchAsksForSoftwareInTheConfiguredStorefront() throws {
        let items = try queryItems(of: ITunesEndpoint.search(term: "spotify"))

        XCTAssertEqual(items, [
            "term": "spotify",
            "media": "software",
            "country": "tr",
            "limit": "25"
        ])
    }

    func testSearchPercentEncodesTurkishCharactersAndSpaces() throws {
        let request = try ITunesEndpoint.search(term: "şarkı sözleri")

        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.contains("term=%C5%9Fark%C4%B1%20s%C3%B6zleri"), url.absoluteString)
        XCTAssertEqual(try queryItems(of: request)["term"], "şarkı sözleri")
    }

    func testSearchPercentEncodesPlusSigns() throws {
        let request = try ITunesEndpoint.search(term: "c++")

        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.absoluteString.contains("term=c%2B%2B"), url.absoluteString)
        XCTAssertEqual(try queryItems(of: request)["term"], "c++")
    }
}
