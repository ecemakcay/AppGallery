import XCTest
@testable import AppGallery

@MainActor
final class SearchConfiguratorTests: XCTestCase {

    func testLoadingTheViewAsksTheInteractorForTheInitialState() {
        let worker = ControllableSearchWorker()
        let viewController = SearchConfigurator.makeScene(worker: worker)

        viewController.loadViewIfNeeded()

        XCTAssertNotNil(viewController.interactor)
        XCTAssertEqual(worker.terms, [], "The initial empty query must not be sent")
    }

    /// Guards the ownership described in `SearchConfigurator`: no retain cycle between the VIP parts.
    func testTheSceneIsReleasedTogetherWithItsViewController() {
        weak var weakViewController: SearchViewController?
        weak var weakInteractor: AnyObject?

        autoreleasepool {
            let viewController = SearchConfigurator.makeScene(worker: ControllableSearchWorker())
            viewController.loadViewIfNeeded()
            weakViewController = viewController
            weakInteractor = viewController.interactor
        }

        XCTAssertNil(weakViewController)
        XCTAssertNil(weakInteractor)
    }
}
