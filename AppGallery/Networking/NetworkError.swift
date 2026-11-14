import Foundation

enum NetworkError: Error, Equatable {
    /// The request could not be built.
    case invalidRequest
    /// The device has no usable connection.
    case offline
    /// The server refused the request because of rate limiting (HTTP 403 or 429).
    /// The iTunes Search API allows roughly 20 calls per minute.
    case rateLimited
    /// Any other non-2xx status code.
    case http(statusCode: Int)
    /// The body could not be decoded into the expected type.
    case decoding
    /// The request failed below HTTP for another reason (timeout, DNS, TLS, ...).
    case transport
}
