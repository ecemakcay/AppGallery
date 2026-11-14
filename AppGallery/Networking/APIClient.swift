import Foundation

/// Executes a request and decodes its JSON body.
///
/// The injected `URLSession` is the seam for tests: they pass a session whose
/// requests are answered by a `URLProtocol` stub, so no test touches the network.
struct APIClient: Sendable {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// `@concurrent` makes the hop explicit: the network wait and the JSON decoding
    /// never run on the caller's actor, so calling this from the main actor cannot block the UI.
    @concurrent
    func send<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.transport
        }
        // The iTunes API answers with `Content-Type: text/javascript`, so only the status code is checked.
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 403, 429:
            throw NetworkError.rateLimited
        default:
            throw NetworkError.http(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NetworkError.decoding
        }
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                // One cancellation type for the whole app; callers never show it as an error.
                throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw NetworkError.offline
            default:
                throw NetworkError.transport
            }
        }
    }
}
