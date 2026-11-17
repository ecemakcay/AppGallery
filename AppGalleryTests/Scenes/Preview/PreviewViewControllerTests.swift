import XCTest
@testable import AppGallery

/// Paging through the screenshots of one application. What a single page shows is tested in
/// `PreviewPageViewControllerTests`.
///
/// A swipe is replayed the way the page controller performs it: it asks the data source for the
/// neighbor, shows it, and then tells its delegate that the transition has finished.
@MainActor
final class PreviewViewControllerTests: XCTestCase {

    private let urls = (0..<4).map { URL(fileURLWithPath: "/screenshots/\($0).png") }
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func makeSUT(
        urls: [URL]? = nil,
        startIndex: Int = 2
    ) throws -> (sut: PreviewViewController, pages: UIPageViewController, images: ImageProvidingStub) {
        let images = ImageProvidingStub()
        let sut = PreviewViewController(urls: urls ?? self.urls, startIndex: startIndex, images: images)
        sut.loadViewIfNeeded()
        let pages = try XCTUnwrap(sut.children.first as? UIPageViewController)
        return (sut, pages, images)
    }

    private func page(
        _ direction: UIPageViewController.NavigationDirection,
        of page: UIViewController?,
        in pages: UIPageViewController
    ) -> PreviewPageViewController? {
        guard let page, let dataSource = pages.dataSource else { return nil }
        let neighbor = direction == .forward
            ? dataSource.pageViewController(pages, viewControllerAfter: page)
            : dataSource.pageViewController(pages, viewControllerBefore: page)
        return neighbor as? PreviewPageViewController
    }

    /// Swipes one page in `direction`. `completed: false` is a swipe the user let go of halfway.
    private func swipe(
        _ direction: UIPageViewController.NavigationDirection,
        in pages: UIPageViewController,
        completed: Bool = true
    ) throws {
        let previous = try XCTUnwrap(pages.viewControllers?.first)
        let next = try XCTUnwrap(page(direction, of: previous, in: pages), "There is no page in that direction")
        if completed {
            pages.setViewControllers([next], direction: direction, animated: false)
        }
        pages.delegate?.pageViewController?(
            pages,
            didFinishAnimating: true,
            previousViewControllers: [previous],
            transitionCompleted: completed
        )
    }

    private func counter(in sut: PreviewViewController) -> UILabel? {
        sut.view.descendants(ofType: UILabel.self).first { $0.text?.contains(" / ") == true }
    }

    // MARK: - Opening

    func testItOpensOnTheTappedScreenshot() throws {
        let (sut, _, _) = try makeSUT(startIndex: 2)

        XCTAssertEqual(sut.currentIndex, 2)
        XCTAssertEqual(sut.currentPage?.url, urls[2])
        XCTAssertEqual(counter(in: sut)?.text, "3 / 4")
        XCTAssertEqual(counter(in: sut)?.accessibilityLabel, "Screenshot 3 of 4")
    }

    func testOnlyTheScreenshotOnScreenIsRequested() throws {
        let (sut, _, images) = try makeSUT(startIndex: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = sut
        window.isHidden = false
        self.window = window
        window.layoutIfNeeded()

        // The neighbors are created only when the user swipes towards them.
        XCTAssertEqual(images.requests, [.init(url: urls[2], priority: .high)])
    }

    // MARK: - Paging

    func testThePagesBeforeAndAfterAreTheNeighborsInTheGallery() throws {
        let (sut, pages, _) = try makeSUT(startIndex: 2)

        XCTAssertEqual(page(.reverse, of: sut.currentPage, in: pages)?.url, urls[1])
        XCTAssertEqual(page(.forward, of: sut.currentPage, in: pages)?.url, urls[3])
    }

    func testTheGalleryDoesNotWrapAroundAtEitherEnd() throws {
        let (first, firstPages, _) = try makeSUT(startIndex: 0)
        XCTAssertNil(page(.reverse, of: first.currentPage, in: firstPages))

        let (last, lastPages, _) = try makeSUT(startIndex: urls.count - 1)
        XCTAssertNil(page(.forward, of: last.currentPage, in: lastPages))
    }

    func testSwipingMovesThroughTheGalleryAndUpdatesTheCounter() throws {
        let (sut, pages, _) = try makeSUT(startIndex: 2)

        try swipe(.forward, in: pages)
        XCTAssertEqual(sut.currentIndex, 3)
        XCTAssertEqual(sut.currentPage?.url, urls[3])
        XCTAssertEqual(counter(in: sut)?.text, "4 / 4")

        try swipe(.reverse, in: pages)
        try swipe(.reverse, in: pages)
        XCTAssertEqual(sut.currentIndex, 1)
        XCTAssertEqual(counter(in: sut)?.text, "2 / 4")
    }

    func testASwipeLetGoOfHalfwayKeepsTheCurrentScreenshot() throws {
        let (sut, pages, _) = try makeSUT(startIndex: 2)

        try swipe(.forward, in: pages, completed: false)

        XCTAssertEqual(sut.currentIndex, 2)
        XCTAssertEqual(counter(in: sut)?.text, "3 / 4")
    }

    func testASingleScreenshotHasNoNeighborsAndNoCounter() throws {
        let (sut, pages, _) = try makeSUT(urls: [urls[0]], startIndex: 0)

        XCTAssertNil(page(.reverse, of: sut.currentPage, in: pages))
        XCTAssertNil(page(.forward, of: sut.currentPage, in: pages))
        let counter = try XCTUnwrap(counter(in: sut))
        XCTAssertTrue(counter.superview?.isHidden == true, "“1 / 1” tells the user nothing")
    }
}
