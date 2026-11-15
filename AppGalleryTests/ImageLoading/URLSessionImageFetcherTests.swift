import XCTest
@testable import AppGallery

/// `@MainActor` on purpose: the fetcher is called from the main actor here, exactly as the download
/// manager calls it. Its decoding step traps if it ever runs on the main thread, so a passing
/// test also proves that the work left the main actor.
@MainActor
final class URLSessionImageFetcherTests: XCTestCase {

    private let url = URL(fileURLWithPath: "/screenshot.png")

    private func makePNG(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testDownloadsAndDecodesAnImageOffTheMainThread() async throws {
        let session = StubURLProtocol.makeSession(body: makePNG(width: 4, height: 8))
        let fetcher = URLSessionImageFetcher(session: session)

        let image = try await fetcher.image(from: url)

        XCTAssertEqual(image.size, CGSize(width: 4, height: 8))
    }

    func testThrowsForDataThatIsNotAnImage() async {
        let session = StubURLProtocol.makeSession(body: Data("not an image".utf8))
        let fetcher = URLSessionImageFetcher(session: session)

        await assertThrows(ImageFetchError.invalidImageData) {
            try await fetcher.image(from: self.url)
        }
    }

    func testThrowsForANon2xxResponse() async {
        let session = StubURLProtocol.makeSession(statusCode: 404, body: makePNG(width: 4, height: 8))
        let fetcher = URLSessionImageFetcher(session: session)

        await assertThrows(ImageFetchError.badResponse) {
            try await fetcher.image(from: self.url)
        }
    }
}
