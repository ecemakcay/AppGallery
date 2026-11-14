import os
import XCTest
@testable import AppGallery

/// Hands out expectations that are fulfilled once a counter has reached a given value.
/// Tests use them to wait for an event instead of sleeping.
@MainActor
final class CountExpectations {

    private var count = 0
    private var pending: [(target: Int, expectation: XCTestExpectation)] = []

    func increment() {
        count += 1
        pending.removeAll { entry in
            guard count >= entry.target else { return false }
            entry.expectation.fulfill()
            return true
        }
    }

    func expectation(forCount target: Int, description: String) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: description)
        if count >= target {
            expectation.fulfill()
        } else {
            pending.append((target, expectation))
        }
        return expectation
    }
}

/// A worker whose calls stay suspended until the test completes them,
/// so the test decides in which order responses arrive.
///
/// Like a request that is already on the wire, a call does not return when its task is cancelled;
/// it only records the cancellation.
@MainActor
final class ControllableSearchWorker: SearchWorkingLogic {

    private(set) var terms: [String] = []
    private var continuations: [CheckedContinuation<[AppResult], any Error>] = []
    private let calls = CountExpectations()
    /// Behind a lock because a cancellation handler may run on any thread.
    private let cancelled = OSAllocatedUnfairLock<[Int]>(initialState: [])

    /// Indexes of the calls whose task was cancelled while they were running (0 is the first call).
    var cancelledCalls: [Int] {
        cancelled.withLock { $0 }
    }

    func fetchApps(matching term: String) async throws -> [AppResult] {
        let index = terms.count
        terms.append(term)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
                calls.increment()
            }
        } onCancel: { [cancelled] in
            cancelled.withLock { $0.append(index) }
        }
    }

    /// Fulfilled once the worker has received `count` calls.
    func expectCalls(_ count: Int) -> XCTestExpectation {
        calls.expectation(forCount: count, description: "\(count) fetch call(s)")
    }

    /// Finishes the call with the given index (0 is the first call). Each call must be completed exactly once.
    func complete(call index: Int, with result: Result<[AppResult], any Error>) {
        continuations[index].resume(with: result)
    }
}

/// Stands in for `Task.sleep`: every wait stays suspended until the test ends it,
/// so the test decides when the debounce is over.
@MainActor
final class ControllableSleeper {

    private(set) var durations: [Duration] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private let calls = CountExpectations()

    func sleep(for duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            calls.increment()
        }
    }

    /// Fulfilled once `count` waits have started.
    func expectCalls(_ count: Int) -> XCTestExpectation {
        calls.expectation(forCount: count, description: "\(count) debounce wait(s)")
    }

    /// Ends the wait with the given index (0 is the first wait). Each wait must be ended exactly once.
    func finish(call index: Int) {
        continuations[index].resume()
    }
}

@MainActor
final class SearchPresenterSpy: SearchPresentationLogic {

    private(set) var responses: [Search.FetchApps.Response] = []
    private let presentations = CountExpectations()

    func presentApps(response: Search.FetchApps.Response) {
        responses.append(response)
        presentations.increment()
    }

    /// Fulfilled once the presenter has received `count` responses.
    func expectResponses(_ count: Int) -> XCTestExpectation {
        presentations.expectation(forCount: count, description: "\(count) response(s)")
    }
}

@MainActor
final class SearchDisplaySpy: SearchDisplayLogic {

    private(set) var viewModels: [Search.FetchApps.ViewModel] = []

    func displayApps(viewModel: Search.FetchApps.ViewModel) {
        viewModels.append(viewModel)
    }
}

extension Search.FetchApps.Response {

    /// `Response` carries an `Error`, so it cannot be `Equatable`. Tests compare this text instead.
    var summary: String {
        switch self {
        case .idle: return "idle"
        case .loading: return "loading"
        case .loaded(let apps): return "loaded(\(apps.map { $0.name ?? "-" }.joined(separator: ", ")))"
        case .failed(let error): return "failed(\(error))"
        }
    }
}

extension AppResult {

    /// `name` is also used in the screenshot URLs, so keep it to a single word.
    static func stub(_ name: String, developer: String? = "Developer", screenshots: Int = 2) -> AppResult {
        AppResult(
            name: name,
            developer: developer,
            screenshotURLs: (0..<screenshots).compactMap { URL(string: "https://example.com/\(name)/\($0).png") }
        )
    }
}
