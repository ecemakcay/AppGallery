import Foundation

@MainActor
protocol SearchBusinessLogic: AnyObject {
    func fetchApps(request: Search.FetchApps.Request)
    func retryLastQuery()
    func selectScreenshot(request: Search.SelectScreenshot.Request)
}

@MainActor
protocol SearchDataStore: AnyObject {
    /// The applications currently on screen, in API order.
    var apps: [AppResult] { get }
    /// The screenshot the user tapped last, with the rest of its application's gallery,
    /// for the router to hand to the preview.
    var selectedScreenshot: Search.SelectScreenshot.Selection? { get }
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
    private let imageDownloader: any ImageDownloading
    private let debounce: Duration
    /// How the debounce waits. Injected so that tests control time instead of sleeping.
    private let sleep: (Duration) async throws -> Void

    private(set) var apps: [AppResult] = []
    private(set) var selectedScreenshot: Search.SelectScreenshot.Selection?

    /// The trimmed query that is displayed or being searched for. `nil` until the first request.
    private var currentQuery: String?
    /// Incremented for every new search. A response is used only if its generation is still the current one.
    private var generation = 0
    /// The running search, if any. Readable so that tests can await a search to its very end.
    private(set) var searchTask: Task<Void, Never>?

    init(
        presenter: any SearchPresentationLogic,
        worker: any SearchWorkingLogic,
        imageDownloader: any ImageDownloading,
        debounce: Duration = .milliseconds(350),
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.presenter = presenter
        self.worker = worker
        self.imageDownloader = imageDownloader
        self.debounce = debounce
        self.sleep = sleep
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

    func selectScreenshot(request: Search.SelectScreenshot.Request) {
        // The indexes come from the screen. They are checked instead of trusted, so a tap that
        // races with a change of results selects nothing rather than crashing.
        guard apps.indices.contains(request.appIndex),
              apps[request.appIndex].screenshotURLs.indices.contains(request.screenshotIndex) else {
            selectedScreenshot = nil
            return
        }
        selectedScreenshot = Search.SelectScreenshot.Selection(
            screenshotURLs: apps[request.appIndex].screenshotURLs,
            index: request.screenshotIndex
        )
    }

    // MARK: - Search

    private func startSearch(for query: String, after delay: Duration) {
        currentQuery = query
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        apps = []
        selectedScreenshot = nil
        // The screenshots of the previous results are no longer wanted.
        imageDownloader.cancelAll()

        guard query.count >= Self.minimumQueryLength else {
            presenter.presentApps(response: .idle)
            return
        }
        // Shown at once, so results of an older query are never on screen while a search is pending.
        presenter.presentApps(response: .loading)

        let generation = generation
        searchTask = Task { [weak self, worker, sleep] in
            let result: Result<[AppResult], any Error>
            do {
                // Debounce: a newer query cancels this task while it waits, so nothing is sent for this one.
                if delay > .zero {
                    try await sleep(delay)
                }
                try Task.checkCancellation()
                result = .success(try await worker.fetchApps(matching: query))
            } catch {
                result = .failure(error)
            }
            self?.finishSearch(generation: generation, query: query, result: result)
        }
    }

    private func finishSearch(generation: Int, query: String, result: Result<[AppResult], any Error>) {
        // Cancellation only asks the old request to stop. This check is what guarantees that a
        // response which still arrives for an older query can never replace newer results.
        guard generation == self.generation else { return }
        searchTask = nil

        switch result {
        case .success(let apps):
            self.apps = apps
            // The case asks for every screenshot to be downloaded, so all of them are queued now,
            // whether or not their cells are visible. The manager keeps at most 3 in flight.
            imageDownloader.enqueue(apps.flatMap(\.screenshotURLs))
            presenter.presentApps(response: .loaded(query: query, apps: apps))
        case .failure(let error) where error is CancellationError:
            break
        case .failure(let error):
            presenter.presentApps(response: .failed(error))
        }
    }
}
