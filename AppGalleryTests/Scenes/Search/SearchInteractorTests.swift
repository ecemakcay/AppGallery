import XCTest
@testable import AppGallery

/// Everything here runs on the main actor: the interactor, the doubles and the tests.
///
/// Tests never sleep and never guess when asynchronous work is done. They wait in two ways:
/// for an event that must happen, with an expectation; and for a search that must have no
/// effect, by waiting for the end of its task: once a task has ended, everything it does has happened.
@MainActor
final class SearchInteractorTests: XCTestCase {

    private let spotify = [AppResult.stub("Spotify"), AppResult.stub("SpotifyKids")]
    private let youtube = [AppResult.stub("YouTube")]

    private typealias SUT = (
        sut: SearchInteractor,
        presenter: SearchPresenterSpy,
        worker: ControllableSearchWorker,
        downloader: ImageDownloadingSpy
    )

    private func makeSUT() -> SUT {
        let presenter = SearchPresenterSpy()
        let worker = ControllableSearchWorker()
        let downloader = ImageDownloadingSpy()
        let sut = SearchInteractor(presenter: presenter, worker: worker, imageDownloader: downloader, debounce: .zero)
        return (sut, presenter, worker, downloader)
    }

    private func wait(for expectation: XCTestExpectation) async {
        await fulfillment(of: [expectation], timeout: 2)
    }

    // MARK: - Queries that are not sent

    func testTheFirstEmptyQueryPresentsIdleWithoutSearching() {
        let (sut, presenter, worker, _) = makeSUT()

        sut.fetchApps(request: .init(query: ""))

        XCTAssertEqual(presenter.responses.map(\.summary), ["idle"])
        XCTAssertEqual(worker.terms, [])
    }

    func testAQueryShorterThanTwoCharactersPresentsIdleWithoutSearching() {
        let (sut, presenter, worker, _) = makeSUT()

        sut.fetchApps(request: .init(query: " a "))

        XCTAssertEqual(presenter.responses.map(\.summary), ["idle"])
        XCTAssertEqual(worker.terms, [])
    }

    func testAnIdenticalQuerySendsNoSecondRequest() async {
        let (sut, presenter, worker, _) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(2))

        // Only whitespace differs, so this is the query that is already displayed.
        sut.fetchApps(request: .init(query: "  spotify "))

        XCTAssertNil(sut.searchTask, "No new search was started")
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loaded(Spotify, SpotifyKids)"])
        XCTAssertEqual(worker.terms, ["spotify"])
    }

    func testAnIdenticalQueryWhileTheRequestIsRunningLeavesItAlone() async throws {
        let (sut, presenter, worker, _) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        let search = try XCTUnwrap(sut.searchTask)
        await wait(for: worker.expectCalls(1))

        sut.fetchApps(request: .init(query: " spotify"))

        XCTAssertEqual(sut.searchTask, search, "The running search was not replaced")
        XCTAssertEqual(worker.cancelledCalls, [])
        worker.complete(call: 0, with: .success(spotify))
        await waitForEnd(of: search)
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loaded(Spotify, SpotifyKids)"])
        XCTAssertEqual(worker.terms, ["spotify"])
    }

    // MARK: - Successful search

    func testANewQueryPresentsLoadingAtOnce() async {
        let (sut, presenter, worker, _) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))

        // Asserted before anything is awaited: loading is presented synchronously.
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading"])

        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success([]))
        await wait(for: presenter.expectResponses(2))
    }

    func testASuccessfulSearchPresentsAndStoresTheApps() async {
        let (sut, presenter, worker, _) = makeSUT()

        sut.fetchApps(request: .init(query: "  spotify "))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(2))

        XCTAssertEqual(worker.terms, ["spotify"], "The query is trimmed before it is sent")
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loaded(Spotify, SpotifyKids)"])
        XCTAssertEqual(sut.apps, spotify)
    }

    // MARK: - Changing the query

    func testQueriesReplacedBeforeTheirSearchStartsAreNeverSent() async {
        let (sut, presenter, worker, _) = makeSUT()

        // No suspension between these calls: each one cancels the previous task before it has run.
        // The debounce itself is covered in SearchInteractorDebounceTests.
        sut.fetchApps(request: .init(query: "sp"))
        sut.fetchApps(request: .init(query: "spo"))
        sut.fetchApps(request: .init(query: "spot"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(4))

        XCTAssertEqual(worker.terms, ["spot"])
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loading", "loading", "loaded(Spotify, SpotifyKids)"])
    }

    func testAChangedQueryCancelsTheRunningRequest() async throws {
        let (sut, presenter, worker, _) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        let oldSearch = try XCTUnwrap(sut.searchTask)
        await wait(for: worker.expectCalls(1))
        XCTAssertEqual(worker.cancelledCalls, [])

        sut.fetchApps(request: .init(query: "youtube"))

        // Cancellation is delivered synchronously, so it is visible right away.
        XCTAssertEqual(worker.cancelledCalls, [0])

        await wait(for: worker.expectCalls(2))
        worker.complete(call: 0, with: .failure(CancellationError()))
        worker.complete(call: 1, with: .success(youtube))
        await waitForEnd(of: oldSearch)
        await wait(for: presenter.expectResponses(3))
        XCTAssertEqual(worker.cancelledCalls, [0], "The new request is not cancelled")
    }

    func testAResponseForAnOlderQueryNeverReplacesNewerResults() async throws {
        let (sut, presenter, worker, downloader) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        let staleSearch = try XCTUnwrap(sut.searchTask)
        await wait(for: worker.expectCalls(1))
        sut.fetchApps(request: .init(query: "youtube"))
        await wait(for: worker.expectCalls(2))
        XCTAssertEqual(sut.apps, [], "A changed query clears the stored apps")

        worker.complete(call: 1, with: .success(youtube))
        await wait(for: presenter.expectResponses(3))
        // The old request ignored its cancellation and answers after the newer one.
        worker.complete(call: 0, with: .success(spotify))
        await waitForEnd(of: staleSearch)

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "loading", "loaded(YouTube)"])
        XCTAssertEqual(sut.apps, youtube)
        XCTAssertEqual(
            downloader.calls,
            [.cancelAll, .cancelAll, .enqueue(youtube.flatMap(\.screenshotURLs))],
            "The stale response queues nothing"
        )
    }

    func testClearingTheQueryReturnsToIdleAndIgnoresTheLateResponse() async throws {
        let (sut, presenter, worker, _) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        let clearedSearch = try XCTUnwrap(sut.searchTask)
        await wait(for: worker.expectCalls(1))

        sut.fetchApps(request: .init(query: ""))

        XCTAssertEqual(worker.cancelledCalls, [0])
        XCTAssertNil(sut.searchTask)
        worker.complete(call: 0, with: .success(spotify))
        await waitForEnd(of: clearedSearch)
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "idle"])
        XCTAssertEqual(sut.apps, [])
    }

    // MARK: - Failure

    func testAFailedSearchPresentsTheError() async {
        let (sut, presenter, worker, _) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .failure(NetworkError.offline))
        await wait(for: presenter.expectResponses(2))

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading", "failed(offline)"])
        XCTAssertEqual(sut.apps, [])
    }

    func testACancelledSearchPresentsNothing() async throws {
        let (sut, presenter, worker, _) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))
        let search = try XCTUnwrap(sut.searchTask)
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .failure(CancellationError()))
        await waitForEnd(of: search)

        XCTAssertEqual(presenter.responses.map(\.summary), ["loading"])
    }

    // MARK: - Retry

    func testRetrySendsTheLastQueryAgain() async {
        let (sut, presenter, worker, _) = makeSUT()
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
        let (sut, presenter, worker, _) = makeSUT()

        sut.retryLastQuery()

        XCTAssertEqual(presenter.responses.map(\.summary), [])
        XCTAssertEqual(worker.terms, [])
    }

    // MARK: - Screenshot downloads

    func testASuccessfulSearchQueuesEveryScreenshotInOrder() async {
        let (sut, presenter, worker, downloader) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(2))

        XCTAssertEqual(downloader.calls, [.cancelAll, .enqueue(spotify.flatMap(\.screenshotURLs))])
    }

    func testAChangedQueryCancelsTheDownloadsAtOnce() async {
        let (sut, presenter, worker, downloader) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(2))

        sut.fetchApps(request: .init(query: "youtube"))

        // Asserted before anything is awaited: the old screenshots are dropped synchronously.
        XCTAssertEqual(
            downloader.calls,
            [.cancelAll, .enqueue(spotify.flatMap(\.screenshotURLs)), .cancelAll]
        )
        await wait(for: worker.expectCalls(2))
        worker.complete(call: 1, with: .success(youtube))
        await wait(for: presenter.expectResponses(4))
        XCTAssertEqual(downloader.calls.last, .enqueue(youtube.flatMap(\.screenshotURLs)))
    }

    func testClearingTheQueryCancelsTheDownloads() async {
        let (sut, presenter, worker, downloader) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .success(spotify))
        await wait(for: presenter.expectResponses(2))

        sut.fetchApps(request: .init(query: ""))

        XCTAssertEqual(
            downloader.calls,
            [.cancelAll, .enqueue(spotify.flatMap(\.screenshotURLs)), .cancelAll]
        )
    }

    func testAFailedSearchQueuesNothing() async {
        let (sut, presenter, worker, downloader) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .failure(NetworkError.offline))
        await wait(for: presenter.expectResponses(2))

        XCTAssertEqual(downloader.calls, [.cancelAll])
    }

    // MARK: - Lifetime

    func testReleasingTheInteractorCancelsTheRunningRequest() async throws {
        let presenter = SearchPresenterSpy()
        let worker = ControllableSearchWorker()
        var sut: SearchInteractor? = SearchInteractor(
            presenter: presenter,
            worker: worker,
            imageDownloader: ImageDownloadingSpy(),
            debounce: .zero
        )
        sut?.fetchApps(request: .init(query: "spotify"))
        let search = try XCTUnwrap(sut?.searchTask)
        await wait(for: worker.expectCalls(1))
        weak var weakSUT: SearchInteractor?
        weakSUT = sut

        sut = nil

        XCTAssertNil(weakSUT, "The running task must not keep the interactor alive")
        XCTAssertEqual(worker.cancelledCalls, [0])
        worker.complete(call: 0, with: .failure(CancellationError()))
        await waitForEnd(of: search)
        XCTAssertEqual(presenter.responses.map(\.summary), ["loading"])
    }
}
