import XCTest
@testable import AppGallery

@MainActor
final class SearchPresenterTests: XCTestCase {

    private func present(_ response: Search.FetchApps.Response) -> Search.FetchApps.ViewModel? {
        let viewController = SearchDisplaySpy()
        let sut = SearchPresenter()
        sut.viewController = viewController

        sut.presentApps(response: response)

        XCTAssertEqual(viewController.viewModels.count, 1)
        return viewController.viewModels.first
    }

    // MARK: - States

    func testIdleShowsTheSearchHint() {
        XCTAssertEqual(present(.idle), .message("Search for an application to see its screenshots."))
    }

    func testLoadingShowsLoading() {
        XCTAssertEqual(present(.loading), .loading)
    }

    func testNoResultsShowsAMessage() {
        XCTAssertEqual(present(.loaded(query: "spotify", apps: [])), .message("No applications found."))
    }

    // MARK: - Results

    func testResultsBecomeOneSectionPerAppInTheSameOrder() {
        let first = AppResult.stub("Spotify", developer: "Spotify AB", screenshots: 3)
        let second = AppResult.stub("YouTube", developer: "Google", screenshots: 1)

        let viewModel = present(.loaded(query: "music", apps: [first, second]))

        XCTAssertEqual(viewModel, .results(summary: "2 results for “music”", sections: [
            Search.AppSection(
                title: "Spotify",
                developer: "Spotify AB",
                screenshotCountText: "3 screenshots",
                screenshotURLs: first.screenshotURLs
            ),
            Search.AppSection(
                title: "YouTube",
                developer: "Google",
                screenshotCountText: "1 screenshot",
                screenshotURLs: second.screenshotURLs
            )
        ]))
    }

    func testTheSummaryOfASingleResultIsSingular() {
        let viewModel = present(.loaded(query: "spotify", apps: [.stub("Spotify")]))

        guard case .results(let summary, _) = viewModel else {
            return XCTFail("Expected results, got \(String(describing: viewModel))")
        }
        XCTAssertEqual(summary, "1 result for “spotify”")
    }

    func testAnAppWithoutScreenshotsKeepsItsSection() {
        let viewModel = present(.loaded(query: "spotify", apps: [.stub("Spotify", screenshots: 0)]))

        guard case .results(_, let sections) = viewModel else {
            return XCTFail("Expected results, got \(String(describing: viewModel))")
        }
        XCTAssertEqual(sections.map(\.screenshotCountText), ["No screenshots"])
        XCTAssertEqual(sections.map(\.screenshotURLs), [[]])
    }

    func testMissingNameAndDeveloperGetFallbackTexts() {
        let viewModel = present(.loaded(query: "spotify", apps: [AppResult(name: nil, developer: nil, screenshotURLs: [])]))

        guard case .results(_, let sections) = viewModel else {
            return XCTFail("Expected results, got \(String(describing: viewModel))")
        }
        XCTAssertEqual(sections.map(\.title), ["Unknown application"])
        XCTAssertEqual(sections.map(\.developer), [""])
    }

    // MARK: - Errors

    func testOfflineErrorExplainsTheConnectionProblem() {
        XCTAssertEqual(
            present(.failed(NetworkError.offline)),
            .error(message: "No internet connection. Check your connection and try again.")
        )
    }

    func testRateLimitErrorAsksToTryAgainLater() {
        XCTAssertEqual(
            present(.failed(NetworkError.rateLimited)),
            .error(message: "Too many requests. Please try again in a moment.")
        )
    }

    func testOtherErrorsShowAGenericMessageInsteadOfTechnicalDetails() {
        let generic = Search.FetchApps.ViewModel.error(message: "Something went wrong. Please try again.")

        XCTAssertEqual(present(.failed(NetworkError.http(statusCode: 500))), generic)
        XCTAssertEqual(present(.failed(NetworkError.decoding)), generic)
        XCTAssertEqual(present(.failed(URLError(.badURL))), generic)
    }
}
