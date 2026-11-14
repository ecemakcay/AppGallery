import Foundation

/// Body of `GET https://itunes.apple.com/search`.
struct SearchResponse: Decodable, Equatable, Sendable {
    let results: [AppResult]
}

/// One application in the search results. Only the fields the app shows are decoded.
struct AppResult: Equatable, Sendable {
    let id: Int
    let name: String?
    let developer: String?
    let screenshotURLs: [URL]
}

extension AppResult: Decodable {

    private enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case name = "trackName"
        case developer = "artistName"
        case screenshotURLs = "screenshotUrls"
    }

    /// Written by hand so that a missing optional field or a malformed URL string
    /// drops only that piece instead of failing the whole response.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        let urlStrings = try container.decodeIfPresent([String].self, forKey: .screenshotURLs) ?? []
        screenshotURLs = urlStrings.compactMap(URL.init(string:))
    }
}
