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
        XCTAssertEqual(present(.loaded([])), .message("No applications found."))
    }

    // MARK: - Results

    func testResultsBecomeOneSectionPerAppInTheSameOrder() {
        let first = AppResult.stub(id: 1, name: "Spotify", developer: "Spotify AB", screenshots: 3)
        let second = AppResult.stub(id: 2, name: "YouTube", developer: "Google", screenshots: 1)

        let viewModel = present(.loaded([first, second]))

        XCTAssertEqual(viewModel, .results([
            Search.AppSection(
                title: "Spotify",
                subtitle: "Spotify AB",
                screenshotCountText: "3 screenshots",
                screenshotURLs: first.screenshotURLs
            ),
            Search.AppSection(
                title: "YouTube",
                subtitle: "Google",
                screenshotCountText: "1 screenshot",
                screenshotURLs: second.screenshotURLs
            )
        ]))
    }

    func testAnAppWithoutScreenshotsKeepsItsSection() {
        let viewModel = present(.loaded([.stub(id: 1, screenshots: 0)]))

        guard case .results(let sections) = viewModel else {
            return XCTFail("Expected results, got \(String(describing: viewModel))")
        }
        XCTAssertEqual(sections.map(\.screenshotCountText), ["No screenshots"])
        XCTAssertEqual(sections.map(\.screenshotURLs), [[]])
    }

    func testMissingNameAndDeveloperGetFallbackTexts() {
        let viewModel = present(.loaded([.stub(id: 1, name: nil, developer: nil)]))

        guard case .results(let sections) = viewModel else {
            return XCTFail("Expected results, got \(String(describing: viewModel))")
        }
        XCTAssertEqual(sections.map(\.title), ["Unknown application"])
        XCTAssertEqual(sections.map(\.subtitle), [""])
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
