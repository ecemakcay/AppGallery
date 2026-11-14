import XCTest
@testable import AppGallery

final class AppResultDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> AppResult {
        try JSONDecoder().decode(AppResult.self, from: Data(json.utf8))
    }

    func testDecodesTheFieldsTheAppUses() throws {
        let app = try decode("""
        {
            "trackId": 324684580,
            "trackName": "Spotify: Music and Podcasts",
            "artistName": "Spotify",
            "screenshotUrls": ["https://example.com/1.png", "https://example.com/2.png"]
        }
        """)

        XCTAssertEqual(app.id, 324684580)
        XCTAssertEqual(app.name, "Spotify: Music and Podcasts")
        XCTAssertEqual(app.developer, "Spotify")
        XCTAssertEqual(app.screenshotURLs.map(\.absoluteString), ["https://example.com/1.png", "https://example.com/2.png"])
    }

    func testMissingOptionalFieldsDoNotFailDecoding() throws {
        let app = try decode(#"{"trackId": 1}"#)

        XCTAssertEqual(app, AppResult(id: 1, name: nil, developer: nil, screenshotURLs: []))
    }

    func testAMalformedScreenshotURLIsSkipped() throws {
        let app = try decode(#"{"trackId": 1, "screenshotUrls": ["", "https://example.com/2.png"]}"#)

        XCTAssertEqual(app.screenshotURLs.map(\.absoluteString), ["https://example.com/2.png"])
    }

    func testOtherScreenshotArraysAreIgnored() throws {
        let app = try decode("""
        {
            "trackId": 1,
            "screenshotUrls": ["https://example.com/phone.png"],
            "ipadScreenshotUrls": ["https://example.com/pad.png"],
            "appletvScreenshotUrls": ["https://example.com/tv.png"]
        }
        """)

        XCTAssertEqual(app.screenshotURLs.map(\.absoluteString), ["https://example.com/phone.png"])
    }
}
