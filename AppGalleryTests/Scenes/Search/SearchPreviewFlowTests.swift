import XCTest
@testable import AppGallery

/// The preview opened from the real screen: navigation controller, search scene, an active search
/// controller and the real download manager. Only the network is replaced.
///
/// The preview is only safe because nothing can change the query while it is on screen. This checks
/// that presenting and dismissing it, with the search controller active, changes nothing:
/// same query, same results, no new search, no cancelled download.
@MainActor
final class SearchPreviewFlowTests: XCTestCase {

    private var window: UIWindow?
    private var fetcher: ControllableImageFetcher?

    override func tearDown() async throws {
        fetcher?.finishRemainingCalls()
        window?.rootViewController?.dismiss(animated: false)
        window?.isHidden = true
        window = nil
        fetcher = nil
        try await super.tearDown()
    }

    private struct Scene {
        let navigationController: UINavigationController
        let sut: SearchViewController
        let searchController: UISearchController
        let collectionView: UICollectionView
        let worker: ControllableSearchWorker
        let fetcher: ControllableImageFetcher
    }

    private let apps = (0..<2).map { app in
        AppResult(
            name: "App \(app)",
            developer: "Developer",
            screenshotURLs: (0..<6).compactMap { URL(string: "https://example.com/app\(app)/\($0).png") }
        )
    }

    private func makeScene() throws -> Scene {
        let worker = ControllableSearchWorker()
        let fetcher = ControllableImageFetcher()
        self.fetcher = fetcher
        let images = ImageDownloadManager(fetcher: fetcher)
        let sut = SearchConfigurator.makeScene(worker: worker, images: images, debounce: .zero)
        let navigationController = UINavigationController(rootViewController: sut)

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
        navigationController.view.layoutIfNeeded()

        let searchController = try XCTUnwrap(sut.navigationItem.searchController)
        let collectionView = try XCTUnwrap(sut.view.descendants(ofType: UICollectionView.self).first)
        return Scene(
            navigationController: navigationController,
            sut: sut,
            searchController: searchController,
            collectionView: collectionView,
            worker: worker,
            fetcher: fetcher
        )
    }

    /// Types `query` into the active search bar and lets the search finish with `apps`.
    private func search(_ query: String, in scene: Scene) async {
        scene.searchController.isActive = true
        scene.searchController.searchBar.text = query
        // What UIKit calls on every keystroke.
        scene.sut.updateSearchResults(for: scene.searchController)
        await fulfillment(of: [scene.worker.expectCalls(1)], timeout: 2)
        scene.worker.complete(call: 0, with: .success(apps))
        // Results are presented right after the screenshots are queued, in the same main actor job.
        await fulfillment(of: [scene.fetcher.expectStarts(3)], timeout: 2)
        scene.sut.view.layoutIfNeeded()
    }

    /// The view controller at the top of the presentation chain.
    private func topmost(of viewController: UIViewController) -> UIViewController {
        var current = viewController
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) async {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in MainActor.assumeIsolated { condition() } },
            object: nil
        )
        expectation.expectationDescription = description
        await fulfillment(of: [expectation], timeout: 5)
    }

    func testOpeningAndClosingThePreviewDuringAnActiveSearchChangesNothing() async throws {
        let scene = try makeScene()
        await search("spotify", in: scene)
        XCTAssertEqual(scene.collectionView.numberOfSections, 2)
        XCTAssertTrue(scene.searchController.isActive)

        // Tap the second screenshot of the second application.
        let tapped = IndexPath(item: 1, section: 1)
        scene.collectionView.delegate?.collectionView?(scene.collectionView, didSelectItemAt: tapped)

        await waitUntil("the preview is on screen") {
            self.topmost(of: scene.navigationController) is PreviewViewController
        }
        let preview = try XCTUnwrap(topmost(of: scene.navigationController) as? PreviewViewController)
        XCTAssertEqual(preview.modalPresentationStyle, .fullScreen)
        XCTAssertEqual(preview.view.window, window, "The preview is really on screen")

        let close = try XCTUnwrap(preview.view.descendants(ofType: UIButton.self).first { $0.accessibilityLabel == "Close" })
        close.sendActions(for: .touchUpInside)
        await waitUntil("the preview is gone") {
            preview.presentingViewController == nil && preview.view.window == nil
        }

        // Everything the search had is still there.
        XCTAssertEqual(scene.searchController.searchBar.text, "spotify")
        XCTAssertTrue(scene.searchController.isActive)
        XCTAssertEqual(scene.collectionView.numberOfSections, 2)
        if scene.collectionView.numberOfSections == 2 {
            XCTAssertEqual(scene.collectionView.numberOfItems(inSection: 1), 6)
        }
        XCTAssertEqual(scene.worker.terms, ["spotify"], "No new search was started")
        XCTAssertEqual(scene.fetcher.cancelledCalls, [], "No download was cancelled")
        XCTAssertEqual(scene.fetcher.runningCount, 3, "The three downloads are still running")
    }

    func testThePreviewShowsTheScreenshotThatWasTapped() async throws {
        let scene = try makeScene()
        await search("spotify", in: scene)
        let tappedURL = apps[1].screenshotURLs[4]
        let image = UIImage()

        scene.collectionView.delegate?.collectionView?(scene.collectionView, didSelectItemAt: IndexPath(item: 4, section: 1))
        await waitUntil("the preview is on screen") {
            self.topmost(of: scene.navigationController) is PreviewViewController
        }
        let preview = try XCTUnwrap(topmost(of: scene.navigationController) as? PreviewViewController)

        // The tapped screenshot was waiting in the queue; the preview moved it to the front,
        // so it is the next one to start when a slot frees up.
        XCTAssertTrue(preview.showsLoadingIndicator)
        scene.fetcher.finish(call: 0, with: .success(UIImage()))
        await fulfillment(of: [scene.fetcher.expectStarts(4)], timeout: 2)
        XCTAssertEqual(scene.fetcher.startedURLs[3], tappedURL)

        scene.fetcher.finish(call: 3, with: .success(image))
        await waitUntil("the preview shows its image") { preview.displayedImage === image }
        XCTAssertFalse(preview.showsLoadingIndicator)
    }
}
