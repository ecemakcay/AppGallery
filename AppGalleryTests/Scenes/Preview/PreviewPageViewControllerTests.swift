import XCTest
@testable import AppGallery

/// One page of the preview, on its own. It gets a stub in place of the download manager, so the test decides what is in memory,
/// what has failed and when the preview hears about a finished download.
@MainActor
final class PreviewPageViewControllerTests: XCTestCase {

    private let url = URL(fileURLWithPath: "/screenshots/1.png")
    private let otherURL = URL(fileURLWithPath: "/screenshots/2.png")

    private func makeSUT(
        images: [URL: UIImage] = [:],
        failed: Set<URL> = []
    ) -> (sut: PreviewPageViewController, images: ImageProvidingStub) {
        let stub = ImageProvidingStub()
        stub.images = images
        stub.failedURLs = failed
        let sut = PreviewPageViewController(url: url, index: 0, images: stub)
        sut.loadViewIfNeeded()
        appear(sut)
        return (sut, stub)
    }

    /// What the page controller does when the user swipes to this page.
    private func appear(_ sut: PreviewPageViewController) {
        sut.beginAppearanceTransition(true, animated: false)
        sut.endAppearanceTransition()
    }

    /// Ends the stream and waits until the preview has handled everything sent before.
    private func deliverUpdates(from images: ImageProvidingStub, to sut: PreviewPageViewController) async throws {
        let observation = try XCTUnwrap(sut.imageUpdatesTask, "The preview is not observing image updates")
        images.finishUpdates()
        await waitForEnd(of: observation)
    }

    private func tapButton(titled title: String, in sut: PreviewPageViewController) throws {
        let buttons = sut.view.descendants(ofType: UIButton.self)
        let button = try XCTUnwrap(buttons.first { $0.configuration?.title == title }, "No “\(title)” button")
        button.sendActions(for: .touchUpInside)
    }

    // MARK: - Opening

    func testACachedImageIsShownAtOnce() {
        let image = UIImage()
        let (sut, _) = makeSUT(images: [url: image])

        XCTAssertTrue(sut.displayedImage === image)
        XCTAssertFalse(sut.showsLoadingIndicator)
        XCTAssertFalse(sut.showsFailure)
    }

    func testAnImageThatIsNotThereYetIsRequestedWithHighPriorityAndShownAsLoading() {
        let (sut, images) = makeSUT()

        XCTAssertEqual(images.requests, [.init(url: url, priority: .high)])
        XCTAssertNil(sut.displayedImage)
        XCTAssertTrue(sut.showsLoadingIndicator)
        XCTAssertFalse(sut.showsFailure)
    }

    func testAPageThatIsOnlyPreparedRequestsNothing() {
        let stub = ImageProvidingStub()
        let sut = PreviewPageViewController(url: url, index: 0, images: stub)

        // The page controller may build a page the user never swipes to.
        sut.loadViewIfNeeded()

        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertTrue(sut.showsLoadingIndicator)
    }

    func testOpeningThePreviewOfAFailedImageRetriesItAtOnce() {
        let (sut, _) = makeSUT(failed: [url])

        // Opening the preview is itself a high-priority request, which is a retry.
        XCTAssertTrue(sut.showsLoadingIndicator)
        XCTAssertFalse(sut.showsFailure)
    }

    // MARK: - Updates

    func testTheImageAppearsWhenItsDownloadEnds() async throws {
        let (sut, images) = makeSUT()
        let image = UIImage()

        images.images[url] = image
        images.send(url)
        try await deliverUpdates(from: images, to: sut)

        XCTAssertTrue(sut.displayedImage === image)
        XCTAssertFalse(sut.showsLoadingIndicator)
    }

    func testAFailedDownloadShowsTheFailure() async throws {
        let (sut, images) = makeSUT()

        images.failedURLs.insert(url)
        images.send(url)
        try await deliverUpdates(from: images, to: sut)

        XCTAssertTrue(sut.showsFailure)
        XCTAssertFalse(sut.showsLoadingIndicator)
        XCTAssertNil(sut.displayedImage)
    }

    func testUpdatesOfOtherScreenshotsAreIgnored() async throws {
        let (sut, images) = makeSUT()

        images.images[otherURL] = UIImage()
        images.send(otherURL)
        try await deliverUpdates(from: images, to: sut)

        XCTAssertNil(sut.displayedImage)
        XCTAssertTrue(sut.showsLoadingIndicator)
    }

    // MARK: - Retry

    func testRetryRequestsTheImageAgainWithHighPriorityAndShowsLoading() async throws {
        let (sut, images) = makeSUT()
        images.failedURLs.insert(url)
        images.send(url)
        let observation = try XCTUnwrap(sut.imageUpdatesTask)
        images.finishUpdates()
        await waitForEnd(of: observation)
        XCTAssertTrue(sut.showsFailure)

        try tapButton(titled: "Retry", in: sut)

        XCTAssertEqual(images.requests, [.init(url: url, priority: .high), .init(url: url, priority: .high)])
        XCTAssertFalse(sut.showsFailure)
        XCTAssertTrue(sut.showsLoadingIndicator)
    }

    // MARK: - Lifetime

    func testReleasingThePageEndsItsSubscription() async {
        let images = ImageProvidingStub()
        weak var weakSUT: PreviewPageViewController?

        autoreleasepool {
            let sut = PreviewPageViewController(url: url, index: 0, images: images)
            sut.loadViewIfNeeded()
            weakSUT = sut
        }

        XCTAssertNil(weakSUT, "The observation task must not keep the page alive")
        await fulfillment(of: [images.subscriptionEnded], timeout: 2)
    }
}
