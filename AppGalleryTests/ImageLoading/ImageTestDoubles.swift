import os
import XCTest
@testable import AppGallery

/// A fetcher whose calls stay suspended until the test finishes them.
///
/// It counts for itself how many calls run at the same time, so tests measure the real concurrency
/// instead of trusting the manager's own counter. Like a request that is still winding down,
/// a call does not return when its task is cancelled; it returns when the test finishes it.
@MainActor
final class ControllableImageFetcher: ImageFetching {

    /// The URL of every call, in the order the calls started. A call's index is its position here.
    private(set) var startedURLs: [URL] = []
    private(set) var runningCount = 0
    /// The highest number of calls that were ever running at the same time.
    private(set) var peakRunningCount = 0

    private var continuations: [Int: CheckedContinuation<UIImage, any Error>] = [:]
    private let starts = CountExpectations()
    /// Behind a lock because a cancellation handler may run on any thread.
    private let cancelled = OSAllocatedUnfairLock<[Int]>(initialState: [])

    /// Indexes of the calls whose task was cancelled while they were running.
    var cancelledCalls: [Int] {
        cancelled.withLock { $0.sorted() }
    }

    func image(from url: URL) async throws -> UIImage {
        let index = startedURLs.count
        startedURLs.append(url)
        runningCount += 1
        peakRunningCount = max(peakRunningCount, runningCount)
        defer { runningCount -= 1 }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[index] = continuation
                starts.increment()
            }
        } onCancel: { [cancelled] in
            cancelled.withLock { $0.append(index) }
        }
    }

    /// Fulfilled once `count` calls have started.
    func expectStarts(_ count: Int) -> XCTestExpectation {
        starts.expectation(forCount: count, description: "\(count) image download(s) started")
    }

    /// Lets the call with the given index return. Each call must be finished exactly once.
    func finish(call index: Int, with result: Result<UIImage, any Error> = .success(UIImage())) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
}

/// Subscribes to a manager's updates and keeps what it received, in order.
@MainActor
final class ImageUpdateRecorder {

    private(set) var urls: [URL] = []
    private let updates = CountExpectations()
    private var task: Task<Void, Never>?

    init(observing images: any ImageProviding) {
        let stream = images.updates()
        task = Task { [weak self] in
            for await url in stream {
                self?.urls.append(url)
                self?.updates.increment()
            }
        }
    }

    deinit {
        task?.cancel()
    }

    /// Fulfilled once `count` updates have arrived.
    func expectUpdates(_ count: Int) -> XCTestExpectation {
        updates.expectation(forCount: count, description: "\(count) image update(s)")
    }
}

/// Records what the interactor asks of the download manager.
@MainActor
final class ImageDownloadingSpy: ImageDownloading {

    enum Call: Equatable {
        case enqueue([URL])
        case cancelAll
    }

    private(set) var calls: [Call] = []

    func enqueue(_ urls: [URL]) {
        calls.append(.enqueue(urls))
    }

    func cancelAll() {
        calls.append(.cancelAll)
    }
}
