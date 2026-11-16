import XCTest
@testable import AppGallery

@MainActor
final class SearchConfiguratorTests: XCTestCase {

    private func makeScene(worker: ControllableSearchWorker) -> SearchViewController {
        let images = ImageDownloadManager(fetcher: ControllableImageFetcher())
        return SearchConfigurator.makeScene(worker: worker, images: images)
    }

    /// The hint travels ViewController -> Interactor -> Presenter -> ViewController,
    /// so finding it on screen proves that the whole cycle is wired.
    func testLoadingTheViewShowsTheIdleHintWithoutSearching() {
        let worker = ControllableSearchWorker()
        let viewController = makeScene(worker: worker)

        viewController.loadViewIfNeeded()

        XCTAssertTrue(viewController.view.showsLabel(withText: "Search for an application to see its screenshots."))
        XCTAssertEqual(worker.terms, [], "The initial empty query must not be sent")
    }

    func testTheRouterIsWiredToTheViewControllerAndToTheInteractorsDataStore() throws {
        let viewController = makeScene(worker: ControllableSearchWorker())

        let router = try XCTUnwrap(viewController.router as? SearchRouter)

        XCTAssertTrue(router.viewController === viewController)
        XCTAssertTrue(router.dataStore === viewController.interactor)
    }

    /// Guards the ownership described in `SearchConfigurator`: no retain cycle between the VIP parts.
    func testTheSceneIsReleasedTogetherWithItsViewController() {
        weak var weakViewController: SearchViewController?
        weak var weakInteractor: AnyObject?
        weak var weakRouter: AnyObject?

        autoreleasepool {
            let viewController = makeScene(worker: ControllableSearchWorker())
            viewController.loadViewIfNeeded()
            weakViewController = viewController
            weakInteractor = viewController.interactor
            weakRouter = viewController.router
        }

        XCTAssertNil(weakViewController)
        XCTAssertNil(weakInteractor)
        XCTAssertNil(weakRouter)
    }
}

private extension UIView {

    /// Whether this view or one of its visible descendants is a label with exactly this text.
    func showsLabel(withText text: String) -> Bool {
        guard !isHidden else { return false }
        if let label = self as? UILabel, label.text == text {
            return true
        }
        return subviews.contains { $0.showsLabel(withText: text) }
    }
}
