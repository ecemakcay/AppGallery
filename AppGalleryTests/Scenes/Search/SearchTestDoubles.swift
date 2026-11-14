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
@MainActor
final class ControllableSearchWorker: SearchWorkingLogic {

    private(set) var terms: [String] = []
    private var continuations: [CheckedContinuation<[AppResult], any Error>] = []
    private let calls = CountExpectations()

    func fetchApps(matching term: String) async throws -> [AppResult] {
        terms.append(term)
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            calls.increment()
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
        case .loaded(let apps): return "loaded\(apps.map(\.id))"
        case .failed(let error): return "failed(\(error))"
        }
    }
}

extension AppResult {

    static func stub(id: Int, name: String? = "App", developer: String? = "Developer", screenshots: Int = 2) -> AppResult {
        AppResult(
            id: id,
            name: name,
            developer: developer,
            screenshotURLs: (0..<screenshots).compactMap { URL(string: "https://example.com/\(id)/\($0).png") }
        )
    }
}
