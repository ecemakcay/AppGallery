import XCTest
@testable import AppGallery

/// The debounce, tested without real time: the interactor waits through a `ControllableSleeper`,
/// and the test decides when each wait is over.
@MainActor
final class SearchInteractorDebounceTests: XCTestCase {

    /// Built with the interactor's default debounce, so these tests also pin its production value.
    private func makeSUT() -> (sut: SearchInteractor, worker: ControllableSearchWorker, sleeper: ControllableSleeper) {
        let worker = ControllableSearchWorker()
        let sleeper = ControllableSleeper()
        let sut = SearchInteractor(
            presenter: SearchPresenterSpy(),
            worker: worker,
            imageDownloader: ImageDownloadingSpy(),
            sleep: { await sleeper.sleep(for: $0) }
        )
        return (sut, worker, sleeper)
    }

    private func wait(for expectation: XCTestExpectation) async {
        await fulfillment(of: [expectation], timeout: 2)
    }

    func testNothingIsSentUntilTheDebounceIsOver() async throws {
        let (sut, worker, sleeper) = makeSUT()

        sut.fetchApps(request: .init(query: "spotify"))
        let search = try XCTUnwrap(sut.searchTask)
        await wait(for: sleeper.expectCalls(1))

        XCTAssertEqual(sleeper.durations, [.milliseconds(350)])
        XCTAssertEqual(worker.terms, [], "The request must wait for the debounce")

        sleeper.finish(call: 0)
        await wait(for: worker.expectCalls(1))

        XCTAssertEqual(worker.terms, ["spotify"])
        worker.complete(call: 0, with: .success([]))
        await waitForEnd(of: search)
    }

    func testAQueryTypedDuringTheDebounceReplacesTheWaitingOne() async throws {
        let (sut, worker, sleeper) = makeSUT()
        sut.fetchApps(request: .init(query: "sp"))
        let replacedSearch = try XCTUnwrap(sut.searchTask)
        await wait(for: sleeper.expectCalls(1))

        // A separate keystroke, arriving while the first query is still waiting.
        sut.fetchApps(request: .init(query: "spo"))
        let currentSearch = try XCTUnwrap(sut.searchTask)
        await wait(for: sleeper.expectCalls(2))

        sleeper.finish(call: 0)
        await waitForEnd(of: replacedSearch)
        XCTAssertEqual(worker.terms, [], "The replaced query is never sent, even after its wait has ended")

        sleeper.finish(call: 1)
        await wait(for: worker.expectCalls(1))
        XCTAssertEqual(worker.terms, ["spo"])
        worker.complete(call: 0, with: .success([]))
        await waitForEnd(of: currentSearch)
    }

    func testRetryDoesNotWaitForTheDebounce() async throws {
        let (sut, worker, sleeper) = makeSUT()
        sut.fetchApps(request: .init(query: "spotify"))
        let failedSearch = try XCTUnwrap(sut.searchTask)
        await wait(for: sleeper.expectCalls(1))
        sleeper.finish(call: 0)
        await wait(for: worker.expectCalls(1))
        worker.complete(call: 0, with: .failure(NetworkError.offline))
        await waitForEnd(of: failedSearch)

        sut.retryLastQuery()
        let retry = try XCTUnwrap(sut.searchTask)
        await wait(for: worker.expectCalls(2))

        XCTAssertEqual(sleeper.durations.count, 1, "Retry sends at once")
        XCTAssertEqual(worker.terms, ["spotify", "spotify"])
        worker.complete(call: 1, with: .success([]))
        await waitForEnd(of: retry)
    }
}
