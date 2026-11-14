import Foundation

/// What the Search interactor needs from the outside world.
///
/// `@MainActor` like the rest of the scene, so the interactor calls it without leaving its actor.
/// The slow part, network and decoding, leaves the main actor inside `APIClient.send`.
@MainActor
protocol SearchWorkingLogic {
    /// Applications matching `term`, in the order the API returned them.
    func fetchApps(matching term: String) async throws -> [AppResult]
}

/// Fetches applications from the iTunes Search API.
struct SearchWorker: SearchWorkingLogic {

    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchApps(matching term: String) async throws -> [AppResult] {
        let request = try ITunesEndpoint.search(term: term)
        let response: SearchResponse = try await apiClient.send(request)
        return response.results
    }
}
