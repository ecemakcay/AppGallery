import XCTest
@testable import AppGallery

/// Everything here runs on the main actor: the interactor, the doubles and the tests.
/// Tests wait for events with expectations and never sleep.
@MainActor
final class SearchInteractorTests: XCTestCase {

    private let spotify = [AppResult.stub("Spotify"), AppResult.stub("SpotifyKids")]
    private let youtube = [AppResult.stub("YouTube")]

    private func makeSUT() -> (sut: SearchInteractor, presenter: SearchPresenterSpy, worker: ControllableSearchWorker) {
        let presenter = SearchPresenterSpy()
        let worker = ControllableSearchWorker()
        let sut = SearchInteractor(presenter: presenter, worker: worker, debounce: .zero)
        return (sut, presenter, worker)
    }

    private func wait(for expectation: XCTestExpectation) async {
        await fulfillment(of: [expectation], timeout: 2)
    }

    // MARK: - Queries that are not sent

    func testTheFirstEmptyQueryPresentsIdleWithoutSearching() {
        let (sut, presenter, worker) = makeSUT()

        sut.fetchApps(request: .init(query: ""))

        XCTAssertEqual(presenter.responses.map(\.summary), ["idle"])
        XCTAssertEqual(worker.terms, [])
    }

    func testAQueryShorterThanTwoCharactersPresentsIdleWithoutSearching() {
        let (sut, presenter, worker) = makeSUT()

        sut.fetchApps(request: .init(query: " a "))

        XCTAssertEqual(presenter.responses.map(\.summary), ["idle"])
        XCTAssertEqual(worker.terms, [])
    }

    func testAnIdenticalQuerySendsNoSecondRequest() async {
        let (sut, presenter, worker) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(2))

        // Only whitespace differs, so this is the query that is already displayed.
        sut.fetchApps(request: .init(query: "  spotify "))

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loaded(Spotify, SpotifyKids)"])
        XCTAssertEqual(worker.terms, ["spotify"])
    }

    // MARK: - Successful search

    func testANewQueryPresentsLoadingAtOnce() async {
        let (sut, presenter, worker) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))

        // Asserted before anything is awaited: loading is presented synchronously.
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading"])

        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success([]))
        await wait(for: presenter.expectResponses(2))
    }

    func testASuccessfulSearchPresentsAndStoresTheApps() async {
        let (sut, presenter, worker) = makeSUT()

        sut.fetchApps(request: .init(query: "  spotify "))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(2))

        XCTAssertEqual(worker.terms, ["spotify"], "The query is trimmed before it is sent")
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loaded(Spotify, SpotifyKids)"])
        XCTAssertEqual(sut.apps, spotify)
    }

    // MARK: - Changing the query

    func testRapidQueryChangesSendOnlyTheLastQuery() async {
        let (sut, presenter, worker) = makeSUT()

        // No suspension between these calls, as when the user types quickly:
        // each call cancels the previous task before its debounce is over.
        sut.fetchApps(request: .init(query: "sp"))
        sut.fetchApps(request: .init(query: "spo"))
        sut.fetchApps(request: .init(query: "spot"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(4))

        XCTAssertEqual(worker.terms, ["spot"])
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loading", "loading", "loaded(Spotify, SpotifyKids)"])
    }

    func testAResponseForAnOlderQueryNeverReplacesNewerResults() async {
        let (sut, presenter, worker) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        sut.fetchApps(request: .init(query: "youtube"))
        await wait(for: worker.expectCalls(2))
        XCTAssertEqual(sut.apps, [], "A changed query clears the stored apps")

        worker.complete(call: 1, with: .success(youtube))
        await wait(for: presenter.expectResponses(3))
        // The old request ignored its cancellation and answers after the newer one.
        worker.complete(call: 0, with: .success(spotify))
        // The stale task was resumed above and the main actor runs its jobs in order,
        // so once this test continues, the stale response has been handled.
        await Task.yield()

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loading", "loaded(YouTube)"])
        XCTAssertEqual(sut.apps, youtube)
    }

    func testClearingTheQueryReturnsToIdleAndIgnoresTheLateResponse() async {
        let (sut, presenter, worker) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))

        sut.fetchApps(request: .init(query: ""))
        worker.complete(call: 0, with: .success(spotify))
        await Task.yield()

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "idle"])
        XCTAssertEqual(sut.apps, [])
    }

    // MARK: - Failure

    func testAFailedSearchPresentsTheError() async {
        let (sut, presenter, worker) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .failure(NetworkError.offline))
        await wait(for: presenter.expectResponses(2))

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "failed(offline)"])
        XCTAssertEqual(sut.apps, [])
    }

    func testACancelledSearchPresentsNothing() async {
        let (sut, presenter, worker) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .failure(CancellationError()))
        await Task.yield()

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading"])
    }

    // MARK: - Retry

    func testRetrySendsTheLastQueryAgain() async {
        let (sut, presenter, worker) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .failure(NetworkError.offline))
        await wait(for: presenter.expectResponses(2))

        sut.retryLastQuery()
        await wait(for: worker.expectCalls(2))
        worker.complete(call: 1, with: .success(spotify))
        await wait(for: presenter.expectResponses(4))

        XCTAssertEqual(worker.terms, ["spotify", "spotify"])
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "failed(offline)", "loading", "loaded(Spotify, SpotifyKids)"])
    }

    func testRetryBeforeAnyQueryDoesNothing() {
        let (sut, presenter, worker) = makeSUT()

        sut.retryLastQuery()

        XCTAssertEqual(presenter.responses.map(\.summary), [])
        XCTAssertEqual(worker.terms, [])
    }
}
