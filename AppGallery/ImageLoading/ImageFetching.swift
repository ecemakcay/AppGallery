import UIKit

/// Downloads one image. The download manager only knows this protocol,
/// so its tests can replace the network with a fetcher they control.
///
/// `@MainActor` like the manager that calls it. The slow part leaves the main actor
/// inside the implementation, explicitly.
@MainActor
protocol ImageFetching {
    func image(from url: URL) async throws -> UIImage
}

enum ImageFetchError: Error, Equatable {
    /// The server did not answer with a 2xx status.
    case badResponse
    /// The body is not an image the system can decode.
    case invalidImageData
}

/// Downloads with `URLSession` and decodes away from the main thread.
struct URLSessionImageFetcher: ImageFetching {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// `@concurrent` makes the hop explicit: neither the network wait nor the decoding
    /// runs on the main actor, even though the caller is the `@MainActor` download manager.
    @concurrent
    func image(from url: URL) async throws -> UIImage {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ImageFetchError.badResponse
        }
        return try Self.decode(data)
    }

    /// Synchronous, so the precondition can check where it really runs.
    /// `preparingForDisplay()` decodes the pixels now, on this thread; without it
    /// the decoding would happen on the main thread when the image is first drawn.
    private nonisolated static func decode(_ data: Data) throws -> UIImage {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let image = UIImage(data: data)?.preparingForDisplay() else {
            throw ImageFetchError.invalidImageData
        }
        return image
    }
}
