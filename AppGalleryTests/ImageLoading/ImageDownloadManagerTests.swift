import XCTest
@testable import AppGallery

/// The download manager, driven through a fetcher the test controls.
///
/// Concurrency is always read from the fetcher (`peakRunningCount`), never from the manager.
/// Nothing here sleeps: tests wait for a download to start or for an update to arrive.
@MainActor
final class ImageDownloadManagerTests: XCTestCase {

    private struct DownloadFailed: Error {}

    private func makeURLs(_ count: Int) -> [URL] {
        (0..<count).compactMap { URL(string: "https://example.com/\($0).png") }
    }

    private func makeSUT(
        maxConcurrentDownloads: Int = 3
    ) -> (sut: ImageDownloadManager, fetcher: ControllableImageFetcher, recorder: ImageUpdateRecorder) {
        let fetcher = ControllableImageFetcher()
        let sut = ImageDownloadManager(fetcher: fetcher, maxConcurrentDownloads: maxConcurrentDownloads)
        return (sut, fetcher, ImageUpdateRecorder(observing: sut))
    }

    private func wait(for expectation: XCTestExpectation) async {
        await fulfillment(of: [expectation], timeout: 2)
    }

    /// Finishes `count` calls successfully, one after the other starting at `firstCall`,
    /// and waits for the update of each before finishing the next.
    private func finishCalls(
        from firstCall: Int,
        count: Int,
        updatesBefore: Int,
        fetcher: ControllableImageFetcher,
        recorder: ImageUpdateRecorder
    ) async {
        for offset in 0..<count {
            await wait(for: fetcher.expectStarts(firstCall + offset + 1))
            fetcher.finish(call: firstCall + offset)
            await wait(for: recorder.expectUpdates(updatesBefore + offset + 1))
        }
    }

    // MARK: - The limit

    func testRunsExactlyThreeDownloadsAtATimeWhenMoreAreQueued() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(10)

        sut.enqueue(urls)
        await wait(for: fetcher.expectStarts(3))
        XCTAssertEqual(fetcher.runningCount, 3)

        await finishCalls(from: 0, count: 10, updatesBefore: 0, fetcher: fetcher, recorder: recorder)

        // Exactly 3, not "at most 3": a manager that downloads one by one must fail this test too.
        XCTAssertEqual(fetcher.peakRunningCount, 3)
        XCTAssertEqual(fetcher.startedURLs, urls)
    }

    func testTheLimitIsConfigurable() async {
        let (sut, fetcher, recorder) = makeSUT(maxConcurrentDownloads: 5)

        sut.enqueue(makeURLs(8))
        await finishCalls(from: 0, count: 8, updatesBefore: 0, fetcher: fetcher, recorder: recorder)

        XCTAssertEqual(fetcher.peakRunningCount, 5)
    }

    func testEveryQueuedURLIsDownloadedExactlyOnce() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(150)

        sut.enqueue(urls)
        await finishCalls(from: 0, count: 150, updatesBefore: 0, fetcher: fetcher, recorder: recorder)

        XCTAssertEqual(fetcher.startedURLs, urls, "Each URL once, in queue order")
        XCTAssertEqual(recorder.urls, urls)
        XCTAssertEqual(fetcher.peakRunningCount, 3)
        XCTAssertTrue(urls.allSatisfy { sut.image(for: $0) != nil })
    }

    // MARK: - Queue order

    func testFinishingADownloadStartsTheNextOneInQueueOrder() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(5)
        sut.enqueue(urls)
        await wait(for: fetcher.expectStarts(3))
        XCTAssertEqual(fetcher.startedURLs, Array(urls[0..<3]))

        fetcher.finish(call: 1)
        await wait(for: fetcher.expectStarts(4))

        XCTAssertEqual(fetcher.startedURLs, Array(urls[0..<4]))
        XCTAssertEqual(fetcher.runningCount, 3)
        fetcher.finish(call: 0)
        fetcher.finish(call: 2)
        await finishCalls(from: 3, count: 2, updatesBefore: 3, fetcher: fetcher, recorder: recorder)
    }

    // MARK: - Results

    func testASuccessfulDownloadIsCachedAndReported() async {
        let (sut, fetcher, recorder) = makeSUT()
        let url = makeURLs(1)[0]
        let image = UIImage()
        XCTAssertNil(sut.image(for: url))

        sut.enqueue([url])
        await wait(for: fetcher.expectStarts(1))
        fetcher.finish(call: 0, with: .success(image))
        await wait(for: recorder.expectUpdates(1))

        XCTAssertTrue(sut.image(for: url) === image)
        XCTAssertFalse(sut.hasFailed(url))
        XCTAssertEqual(recorder.urls, [url])
    }

    func testAFailedDownloadIsReportedAndFreesItsSlot() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(4)
        sut.enqueue(urls)
        await wait(for: fetcher.expectStarts(3))

        fetcher.finish(call: 0, with: .failure(DownloadFailed()))
        await wait(for: recorder.expectUpdates(1))
        await wait(for: fetcher.expectStarts(4))

        XCTAssertTrue(sut.hasFailed(urls[0]))
        XCTAssertNil(sut.image(for: urls[0]))
        XCTAssertEqual(recorder.urls, [urls[0]])
        XCTAssertEqual(fetcher.startedURLs.last, urls[3], "One failure does not stop the queue")
        await finishCalls(from: 1, count: 3, updatesBefore: 1, fetcher: fetcher, recorder: recorder)
    }

    func testEverySubscriberReceivesTheUpdates() async {
        let (sut, fetcher, firstRecorder) = makeSUT()
        let secondRecorder = ImageUpdateRecorder(observing: sut)
        let url = makeURLs(1)[0]

        sut.enqueue([url])
        await wait(for: fetcher.expectStarts(1))
        fetcher.finish(call: 0)
        await wait(for: firstRecorder.expectUpdates(1))
        await wait(for: secondRecorder.expectUpdates(1))

        XCTAssertEqual(firstRecorder.urls, [url])
        XCTAssertEqual(secondRecorder.urls, [url])
    }

    // MARK: - Duplicates

    func testAURLThatIsQueuedRunningOrCachedIsNotDownloadedAgain() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(5)

        // urls[0] is queued twice, and again while it is running.
        sut.enqueue([urls[0], urls[0], urls[1]])
        sut.enqueue([urls[0]])
        await wait(for: fetcher.expectStarts(2))
        sut.enqueue([urls[0]])
        sut.request(urls[0], priority: .normal)
        sut.request(urls[0], priority: .high)
        await finishCalls(from: 0, count: 2, updatesBefore: 0, fetcher: fetcher, recorder: recorder)

        // Now urls[0] and urls[1] are cached. Only the new URLs may be fetched.
        sut.enqueue([urls[0], urls[2]])
        sut.request(urls[1], priority: .high)
        sut.request(urls[3], priority: .normal)
        sut.request(urls[3], priority: .normal)
        await finishCalls(from: 2, count: 2, updatesBefore: 2, fetcher: fetcher, recorder: recorder)

        XCTAssertEqual(fetcher.startedURLs, [urls[0], urls[1], urls[2], urls[3]])
    }

    // MARK: - Priority

    func testAHighPriorityRequestJumpsTheQueueWithoutExceedingTheLimit() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(6)
        let unknown = makeURLs(7)[6]
        sut.enqueue(urls)
        await wait(for: fetcher.expectStarts(3))

        // urls[5] is last in the queue; `unknown` was never queued. The later request goes first.
        sut.request(urls[5], priority: .high)
        sut.request(unknown, priority: .high)
        XCTAssertEqual(fetcher.startedURLs.count, 3, "A running download is never interrupted")

        await finishCalls(from: 0, count: 7, updatesBefore: 0, fetcher: fetcher, recorder: recorder)

        XCTAssertEqual(fetcher.startedURLs, [urls[0], urls[1], urls[2], unknown, urls[5], urls[3], urls[4]])
        XCTAssertEqual(fetcher.peakRunningCount, 3)
    }

    // MARK: - Failures and retry

    func testAFailedURLIsOnlyDownloadedAgainOnAHighPriorityRequest() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(2)
        sut.enqueue([urls[0]])
        await wait(for: fetcher.expectStarts(1))
        fetcher.finish(call: 0, with: .failure(DownloadFailed()))
        await wait(for: recorder.expectUpdates(1))

        // What a cell does when it is configured again must not retry on its own.
        sut.enqueue([urls[0]])
        sut.request(urls[0], priority: .normal)
        // urls[1] is fetched instead; if urls[0] had been queued, it would have started first.
        sut.enqueue([urls[1]])
        await finishCalls(from: 1, count: 1, updatesBefore: 1, fetcher: fetcher, recorder: recorder)
        XCTAssertEqual(fetcher.startedURLs, [urls[0], urls[1]])
        XCTAssertTrue(sut.hasFailed(urls[0]))

        // The explicit retry.
        sut.request(urls[0], priority: .high)
        XCTAssertFalse(sut.hasFailed(urls[0]), "A retried image is loading, not failed")
        await finishCalls(from: 2, count: 1, updatesBefore: 2, fetcher: fetcher, recorder: recorder)

        XCTAssertEqual(fetcher.startedURLs, [urls[0], urls[1], urls[0]])
        XCTAssertNotNil(sut.image(for: urls[0]))
    }

    // MARK: - Cancellation

    func testCancelAllStopsTheRunningDownloadsAndEmptiesTheQueue() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(5)
        let later = makeURLs(6)[5]
        sut.enqueue(urls)
        await wait(for: fetcher.expectStarts(3))

        sut.cancelAll()

        XCTAssertEqual(fetcher.cancelledCalls, [0, 1, 2])
        for call in 0..<3 {
            fetcher.finish(call: call, with: .failure(CancellationError()))
        }
        // A download queued afterwards shows that the cancelled ones gave their slots back
        // and that urls[3] and urls[4] are no longer waiting: `later` is the next to start.
        sut.enqueue([later])
        await finishCalls(from: 3, count: 1, updatesBefore: 0, fetcher: fetcher, recorder: recorder)

        XCTAssertEqual(fetcher.startedURLs, [urls[0], urls[1], urls[2], later])
        XCTAssertEqual(recorder.urls, [later], "Cancelled downloads are not reported")
        XCTAssertFalse(urls.contains { sut.hasFailed($0) }, "A cancellation is not a failure")
    }

    /// The hardest case: the same URLs are queued again while the cancelled requests are still on the wire.
    /// The fetcher keeps cancelled calls running until the test finishes them; a fetcher that returned
    /// on cancellation by itself could not show this bug.
    func testQueueingTheSameURLsRightAfterCancelAllNeverExceedsTheLimit() async {
        let (sut, fetcher, recorder) = makeSUT()
        let urls = makeURLs(5)
        let staleImage = UIImage()
        sut.enqueue(urls)
        await wait(for: fetcher.expectStarts(3))

        sut.cancelAll()
        sut.enqueue(urls)

        // Calls 0, 1 and 2 are cancelled but still running, so they still hold all three slots.
        // The first one now answers late, and even successfully.
        fetcher.finish(call: 0, with: .success(staleImage))
        await wait(for: fetcher.expectStarts(4))

        // Its slot went to the new download of urls[0]; its late image was thrown away.
        XCTAssertEqual(fetcher.startedURLs.count, 4, "Only the freed slot was reused")
        XCTAssertEqual(fetcher.startedURLs[3], urls[0])
        XCTAssertEqual(fetcher.runningCount, 3)
        XCTAssertNil(sut.image(for: urls[0]))

        fetcher.finish(call: 1, with: .failure(CancellationError()))
        fetcher.finish(call: 2, with: .failure(CancellationError()))
        await finishCalls(from: 3, count: 5, updatesBefore: 0, fetcher: fetcher, recorder: recorder)

        XCTAssertEqual(fetcher.peakRunningCount, 3)
        XCTAssertEqual(Array(fetcher.startedURLs[3...]), urls, "Every URL is downloaded for the new request")
        XCTAssertEqual(recorder.urls, urls, "The three stale completions were not reported")
        XCTAssertTrue(urls.allSatisfy { sut.image(for: $0) != nil })
        XCTAssertFalse(sut.image(for: urls[0]) === staleImage)
        XCTAssertFalse(urls.contains { sut.hasFailed($0) })
    }
}
