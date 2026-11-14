import Foundation

/// Body of `GET https://itunes.apple.com/search`.
struct SearchResponse: Decodable, Equatable, Sendable {
    let results: [AppResult]
}

/// One application in the search results. Only the fields the app shows are decoded,
/// and none of them is required: whatever is missing gets a fallback on screen.
struct AppResult: Equatable, Sendable {
    let name: String?
    let developer: String?
    let screenshotURLs: [URL]
}

extension AppResult: Decodable {

    private enum CodingKeys: String, CodingKey {
        case name = "trackName"
        case developer = "artistName"
        case screenshotURLs = "screenshotUrls"
    }

    /// Written by hand so that a missing field or an unusable URL string
    /// drops only that piece instead of failing the whole response.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        let urlStrings = try container.decodeIfPresent([String].self, forKey: .screenshotURLs) ?? []
        screenshotURLs = urlStrings.compactMap(Self.downloadableURL)
    }

    /// `URL(string:)` also accepts relative paths and other schemes, which could never be downloaded.
    /// A screenshot is kept only if it is an absolute web address.
    private static func downloadableURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host(),
              !host.isEmpty
        else {
            return nil
        }
        return url
    }
}
