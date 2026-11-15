import XCTest
@testable import AppGallery

/// How the grid shows images. The view controller gets a stub in place of the download manager,
/// so no download is ever started here and nothing is left running after a test.
///
/// Updates travel the real path: stub's stream -> the view controller's observation task -> the cell.
/// A test sends its updates, ends the stream and waits for the observation task to end; once that
/// task has ended, every update has been handled.
@MainActor
final class SearchViewControllerImageTests: XCTestCase {

    private let urls = (0..<4).compactMap { URL(string: "https://example.com/\($0).png") }

    private func makeSUT(
        images: [URL: UIImage] = [:],
        failed: Set<URL> = []
    ) -> (sut: SearchViewController, images: ImageProvidingStub) {
        let stub = ImageProvidingStub()
        stub.images = images
        stub.failedURLs = failed
        let sut = SearchViewController()
        sut.images = stub
        sut.loadViewIfNeeded()
        sut.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return (sut, stub)
    }

    /// Shows one application with four screenshots; all four cells fit on the screen.
    private func showResults(in sut: SearchViewController) {
        let section = Search.AppSection(
            title: "App",
            subtitle: "Developer",
            screenshotCountText: "\(urls.count) screenshots",
            screenshotURLs: urls
        )
        sut.displayApps(viewModel: .results([section]))
        sut.view.layoutIfNeeded()
    }

    private func cell(showing url: URL, in sut: SearchViewController) throws -> ScreenshotCell {
        let cells = sut.view.descendants(ofType: ScreenshotCell.self)
        return try XCTUnwrap(cells.first { $0.representedURL == url }, "No visible cell shows \(url)")
    }

    /// Ends the stream and waits until the view controller has handled everything sent before.
    private func deliverUpdates(from images: ImageProvidingStub, to sut: SearchViewController) async throws {
        let observation = try XCTUnwrap(sut.imageUpdatesTask, "The view controller is not observing image updates")
        images.finishUpdates()
        await waitForEnd(of: observation)
    }

    // MARK: - Configuring cells

    func testACellWhoseImageIsNotInMemoryShowsThePlaceholderAndAsksForTheImage() throws {
        let (sut, images) = makeSUT()

        showResults(in: sut)

        for url in urls {
            let cell = try cell(showing: url, in: sut)
            XCTAssertNil(cell.displayedImage)
            XCTAssertFalse(cell.showsRetryHint)
        }
        // This is also what brings back an image the cache has dropped.
        XCTAssertEqual(Set(images.requests), Set(urls.map { .init(url: $0, priority: .normal) }))
    }

    func testACachedImageIsShownAtOnceWithoutARequest() throws {
        let image = UIImage()
        let (sut, images) = makeSUT(images: [urls[1]: image])

        showResults(in: sut)

        XCTAssertTrue(try cell(showing: urls[1], in: sut).displayedImage === image)
        XCTAssertFalse(images.requests.contains { $0.url == urls[1] })
    }

    func testAFailedImageShowsTheRetryHintAndIsNotRequestedAgain() throws {
        let (sut, images) = makeSUT(failed: [urls[2]])

        showResults(in: sut)

        XCTAssertTrue(try cell(showing: urls[2], in: sut).showsRetryHint)
        XCTAssertFalse(images.requests.contains { $0.url == urls[2] })
    }

    // MARK: - Updates

    func testAFinishedDownloadReachesOnlyTheCellOfThatScreenshot() async throws {
        let (sut, images) = makeSUT()
        showResults(in: sut)
        let image = UIImage()

        images.images[urls[1]] = image
        images.send(urls[1])
        try await deliverUpdates(from: images, to: sut)

        XCTAssertTrue(try cell(showing: urls[1], in: sut).displayedImage === image)
        for url in urls where url != urls[1] {
            XCTAssertNil(try cell(showing: url, in: sut).displayedImage)
        }
    }

    func testAFailedDownloadTurnsTheCellIntoTheRetryHint() async throws {
        let (sut, images) = makeSUT()
        showResults(in: sut)

        images.failedURLs.insert(urls[0])
        images.send(urls[0])
        try await deliverUpdates(from: images, to: sut)

        XCTAssertTrue(try cell(showing: urls[0], in: sut).showsRetryHint)
        XCTAssertFalse(try cell(showing: urls[1], in: sut).showsRetryHint)
    }

    func testACellReusedForAnotherScreenshotDoesNotGetTheOldImage() async throws {
        let (sut, images) = makeSUT()
        showResults(in: sut)
        let reusedCell = try cell(showing: urls[0], in: sut)
        let otherURL = try XCTUnwrap(URL(string: "https://example.com/other.png"))

        // The cell scrolls away and comes back for another screenshot before the download ends.
        reusedCell.prepareForReuse()
        reusedCell.configure(url: otherURL, state: .loading)
        images.images[urls[0]] = UIImage()
        images.send(urls[0])
        try await deliverUpdates(from: images, to: sut)

        XCTAssertNil(reusedCell.displayedImage)
        XCTAssertEqual(reusedCell.representedURL, otherURL)
    }

    // MARK: - Retry

    func testTappingAFailedCellRetriesWithHighPriorityAndThenShowsTheImage() async throws {
        let (sut, images) = makeSUT(failed: [urls[0]])
        showResults(in: sut)
        let collectionView = try XCTUnwrap(sut.view.descendants(ofType: UICollectionView.self).first)
        let failedCell = try cell(showing: urls[0], in: sut)
        let indexPath = try XCTUnwrap(collectionView.indexPath(for: failedCell))
        let image = UIImage()

        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)

        // Refreshing the cell afterwards also sends its usual normal request, so the retry is not the last one.
        XCTAssertTrue(images.requests.contains(.init(url: urls[0], priority: .high)))
        XCTAssertFalse(failedCell.showsRetryHint, "The cell is loading again")
        XCTAssertNil(failedCell.displayedImage)

        images.images[urls[0]] = image
        images.send(urls[0])
        try await deliverUpdates(from: images, to: sut)

        XCTAssertTrue(failedCell.displayedImage === image)
    }

    func testTappingACellThatHasNotFailedRequestsNothing() throws {
        let (sut, images) = makeSUT()
        showResults(in: sut)
        let collectionView = try XCTUnwrap(sut.view.descendants(ofType: UICollectionView.self).first)
        let indexPath = try XCTUnwrap(collectionView.indexPath(for: try cell(showing: urls[0], in: sut)))
        let requestsBefore = images.requests

        collectionView.delegate?.collectionView?(collectionView, didSelectItemAt: indexPath)

        XCTAssertEqual(images.requests, requestsBefore)
    }

    // MARK: - Lifetime

    func testReleasingTheViewControllerEndsItsSubscription() async {
        let images = ImageProvidingStub()
        weak var weakSUT: SearchViewController?

        autoreleasepool {
            let sut = SearchViewController()
            sut.images = images
            sut.loadViewIfNeeded()
            weakSUT = sut
        }

        XCTAssertNil(weakSUT, "The observation task must not keep the view controller alive")
        await fulfillment(of: [images.subscriptionEnded], timeout: 2)
    }
}

private extension UIView {

    func descendants<View: UIView>(ofType type: View.Type) -> [View] {
        subviews.flatMap { subview in
            ((subview as? View).map { [$0] } ?? []) + subview.descendants(ofType: type)
        }
    }
}
