import Foundation

/// Builds requests for the iTunes Search API.
/// https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/index.html
enum ITunesEndpoint {

    /// Storefront whose catalogue is searched.
    static let country = "tr"
    /// Maximum number of applications returned per search.
    static let resultLimit = 25

    static func search(term: String) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "limit", value: String(resultLimit))
        ]
        // URLComponents leaves "+" untouched and servers read it as a space, so "c++" would arrive as "c  ".
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        guard let url = components.url else {
            throw NetworkError.invalidRequest
        }
        return URLRequest(url: url)
    }
}
