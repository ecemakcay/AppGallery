import XCTest
@testable import AppGallery

final class AppResultDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> AppResult {
        try JSONDecoder().decode(AppResult.self, from: Data(json.utf8))
    }

    private func screenshots(_ urlStrings: [String]) throws -> [String] {
        let json = try JSONEncoder().encode(["screenshotUrls": urlStrings])
        return try JSONDecoder().decode(AppResult.self, from: json).screenshotURLs.map(\.absoluteString)
    }

    // MARK: - Fields

    func testDecodesTheFieldsTheAppUses() throws {
        let app = try decode("""
        {
            "trackId": 324684580,
            "trackName": "Spotify: Music and Podcasts",
            "artistName": "Spotify",
            "screenshotUrls": ["https://example.com/1.png", "https://example.com/2.png"]
        }
        """)

        XCTAssertEqual(app.name, "Spotify: Music and Podcasts")
        XCTAssertEqual(app.developer, "Spotify")
        XCTAssertEqual(app.screenshotURLs.map(\.absoluteString), ["https://example.com/1.png", "https://example.com/2.png"])
    }

    func testAResultWithNoFieldsStillDecodes() throws {
        let app = try decode("{}")

        XCTAssertEqual(app, AppResult(name: nil, developer: nil, screenshotURLs: []))
    }

    func testASparseResultDoesNotCostTheOtherResults() throws {
        let json = """
        {"results": [
            {"trackName": "First", "screenshotUrls": ["https://example.com/1.png"]},
            {},
            {"trackName": "Third", "artistName": null, "screenshotUrls": null}
        ]}
        """

        let response = try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.results.map(\.name), ["First", nil, "Third"])
        XCTAssertEqual(response.results.map(\.screenshotURLs.count), [1, 0, 0])
    }

    func testOtherScreenshotArraysAreIgnored() throws {
        let app = try decode("""
        {
            "screenshotUrls": ["https://example.com/phone.png"],
            "ipadScreenshotUrls": ["https://example.com/pad.png"],
            "appletvScreenshotUrls": ["https://example.com/tv.png"]
        }
        """)

        XCTAssertEqual(app.screenshotURLs.map(\.absoluteString), ["https://example.com/phone.png"])
    }

    // MARK: - Screenshot URLs

    func testOnlyAbsoluteWebAddressesAreKeptInTheirOriginalOrder() throws {
        let kept = try screenshots([
            "https://example.com/1.png",
            "",
            "images/relative.png",
            "/absolute/path.png",
            "file:///tmp/local.png",
            "ftp://example.com/remote.png",
            "https://",
            "http://example.com/2.png",
            "HTTPS://example.com/3.png"
        ])

        XCTAssertEqual(kept, [
            "https://example.com/1.png",
            "http://example.com/2.png",
            "HTTPS://example.com/3.png"
        ])
    }
}
