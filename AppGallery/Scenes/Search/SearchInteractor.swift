import Foundation

@MainActor
protocol SearchBusinessLogic: AnyObject {
    func fetchApps(request: Search.FetchApps.Request)
    func retryLastQuery()
}

@MainActor
protocol SearchDataStore: AnyObject {
    /// The applications currently on screen, in API order.
    var apps: [AppResult] { get }
}

/// Decides when to search and which response is still relevant.
///
/// `@MainActor` because it owns the state that coordinates the UI: the current query,
/// the generation counter and the running task. Its `await`s suspend; they never block the main thread.
@MainActor
final class SearchInteractor: SearchBusinessLogic, SearchDataStore {

    /// Shorter queries are not sent. They match almost everything, and the API allows only about 20 calls per minute.
    static let minimumQueryLength = 2

    private let presenter: any SearchPresentationLogic
    private let worker: any SearchWorkingLogic
    private let debounce: Duration

    private(set) var apps: [AppResult] = []

    /// The trimmed query that is displayed or being searched for. `nil` until the first request.
    private var currentQuery: String?
    /// Incremented for every new search. A response is used only if its generation is still the current one.
    private var generation = 0
    private var searchTask: Task<Void, Never>?

    init(
        presenter: any SearchPresentationLogic,
        worker: any SearchWorkingLogic,
        debounce: Duration = .milliseconds(350)
    ) {
        self.presenter = presenter
        self.worker = worker
        self.debounce = debounce
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: - SearchBusinessLogic

    func fetchApps(request: Search.FetchApps.Request) {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != currentQuery else { return }
        startSearch(for: query, after: debounce)
    }

    func retryLastQuery() {
        guard let currentQuery else { return }
        startSearch(for: currentQuery, after: .zero)
    }

    // MARK: - Search

    private func startSearch(for query: String, after delay: Duration) {
        currentQuery = query
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        apps = []

        guard query.count >= Self.minimumQueryLength else {
            presenter.presentApps(response: .idle)
            return
        }
        // Shown at once, so results of an older query are never on screen while a search is pending.
        presenter.presentApps(response: .loading)

        let generation = generation
        searchTask = Task { [weak self, worker] in
            let result: Result<[AppResult], any Error>
            do {
                // Debounce: a newer query cancels this task while it sleeps, so nothing is sent for this one.
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                result = .success(try await worker.fetchApps(matching: query))
            } catch {
                result = .failure(error)
            }
            self?.finishSearch(generation: generation, result: result)
        }
    }

    private func finishSearch(generation: Int, result: Result<[AppResult], any Error>) {
        // Cancellation only asks the old request to stop. This check is what guarantees that a
        // response which still arrives for an older query can never replace newer results.
        guard generation == self.generation else { return }
        searchTask = nil

        switch result {
        case .success(let apps):
            self.apps = apps
            presenter.presentApps(response: .loaded(apps))
        case .failure(let error) where error is CancellationError:
            break
        case .failure(let error):
            presenter.presentApps(response: .failed(error))
        }
    }
}
