import XCTest
@testable import AppGallery

/// The galleries themselves: two applications with six screenshots each, scrolled for real.
/// Nothing is reconfigured by hand here; cells come and go the way UIKit reuses them.
@MainActor
final class SearchViewControllerGalleryTests: XCTestCase {

    private let screenshotsPerApp = 6

    /// A collection view refers to its data source weakly, so holding the collection view alone would
    /// not keep the view controller alive. The test case owns it for as long as the test runs.
    private var retainedSUT: SearchViewController?

    override func tearDown() async throws {
        retainedSUT = nil
        try await super.tearDown()
    }

    private func urls(ofApp app: Int) -> [URL] {
        (0..<screenshotsPerApp).compactMap { URL(string: "https://example.com/app\(app)/\($0).png") }
    }

    private func makeSUT(
        width: CGFloat = 390,
        images: [URL: UIImage] = [:]
    ) throws -> (sut: SearchViewController, images: ImageProvidingStub, collectionView: UICollectionView) {
        let stub = ImageProvidingStub()
        stub.images = images
        let sut = SearchViewController()
        retainedSUT = sut
        sut.images = stub
        sut.loadViewIfNeeded()
        sut.view.frame = CGRect(x: 0, y: 0, width: width, height: 1400)

        let sections = (0..<2).map { app in
            Search.AppSection(
                title: "App \(app)",
                developer: "Developer",
                screenshotCountText: "\(screenshotsPerApp) screenshots",
                screenshotURLs: urls(ofApp: app)
            )
        }
        sut.displayApps(viewModel: .results(summary: "2 results for “app”", sections: sections))
        sut.view.layoutIfNeeded()

        let collectionView = try XCTUnwrap(sut.view.descendants(ofType: UICollectionView.self).first)
        XCTAssertTrue(collectionView.dataSource === sut)
        return (sut, stub, collectionView)
    }

    private func visibleItems(ofApp app: Int, in collectionView: UICollectionView) -> [Int] {
        collectionView.indexPathsForVisibleItems.filter { $0.section == app }.map(\.item).sorted()
    }

    /// Scrolls one gallery sideways until the given screenshot is on screen.
    private func scroll(_ collectionView: UICollectionView, toScreenshot item: Int, ofApp app: Int) {
        collectionView.scrollToItem(at: IndexPath(item: item, section: app), at: .right, animated: false)
        collectionView.layoutIfNeeded()
    }

    private func deliverUpdates(from images: ImageProvidingStub, to sut: SearchViewController) async throws {
        let observation = try XCTUnwrap(sut.imageUpdatesTask)
        images.finishUpdates()
        await waitForEnd(of: observation)
    }

    // MARK: - Horizontal scrolling

    func testAGalleryStartsAtItsFirstScreenshotsAndTheLastOnesAreOffScreen() throws {
        let (_, _, collectionView) = try makeSUT()

        for app in 0..<2 {
            let items = visibleItems(ofApp: app, in: collectionView)
            XCTAssertEqual(items.first, 0)
            XCTAssertFalse(items.contains(screenshotsPerApp - 1), "Two and a half tiles fit on 390 pt, not six")
        }
    }

    func testScrollingOneGalleryShowsItsLaterScreenshotsAndLeavesTheOtherGalleryAlone() throws {
        let (_, _, collectionView) = try makeSUT()
        let otherGalleryBefore = visibleItems(ofApp: 0, in: collectionView)

        scroll(collectionView, toScreenshot: screenshotsPerApp - 1, ofApp: 1)

        let scrolled = visibleItems(ofApp: 1, in: collectionView)
        XCTAssertTrue(scrolled.contains(screenshotsPerApp - 1))
        XCTAssertFalse(scrolled.contains(0), "The first screenshot scrolled out of view")
        XCTAssertNotNil(collectionView.dataSource, "The view controller is still alive and serving cells")
        XCTAssertEqual(visibleItems(ofApp: 0, in: collectionView), otherGalleryBefore)
    }

    func testAfterScrollingEveryTileShowsTheScreenshotOfItsOwnPosition() throws {
        // Every screenshot has its own image, so a tile that kept the image of the tile
        // it was reused from would be caught here.
        let allURLs = urls(ofApp: 0) + urls(ofApp: 1)
        let images = Dictionary(uniqueKeysWithValues: allURLs.map { ($0, UIImage()) })
        let (_, _, collectionView) = try makeSUT(images: images)

        scroll(collectionView, toScreenshot: screenshotsPerApp - 1, ofApp: 1)
        scroll(collectionView, toScreenshot: 0, ofApp: 1)
        scroll(collectionView, toScreenshot: screenshotsPerApp - 1, ofApp: 0)

        let indexPaths = collectionView.indexPathsForVisibleItems
        XCTAssertFalse(indexPaths.isEmpty)
        for indexPath in indexPaths {
            let cell = try XCTUnwrap(collectionView.cellForItem(at: indexPath) as? ScreenshotCell)
            let expectedURL = urls(ofApp: indexPath.section)[indexPath.item]
            XCTAssertEqual(cell.representedURL, expectedURL, "\(indexPath)")
            XCTAssertTrue(cell.displayedImage === images[expectedURL], "\(indexPath)")
        }
    }

    func testAScreenshotScrolledIntoViewIsRequestedAndReceivesItsImage() async throws {
        let (sut, images, collectionView) = try makeSUT()
        let lastURL = urls(ofApp: 1)[screenshotsPerApp - 1]
        XCTAssertFalse(images.requests.contains { $0.url == lastURL }, "Not on screen yet")

        scroll(collectionView, toScreenshot: screenshotsPerApp - 1, ofApp: 1)
        XCTAssertTrue(images.requests.contains { $0.url == lastURL })

        let image = UIImage()
        images.images[lastURL] = image
        images.send(lastURL)
        try await deliverUpdates(from: images, to: sut)

        let indexPath = IndexPath(item: screenshotsPerApp - 1, section: 1)
        let cell = try XCTUnwrap(collectionView.cellForItem(at: indexPath) as? ScreenshotCell)
        XCTAssertTrue(cell.displayedImage === image)
    }

    func testScrollingAGalleryDoesNotMoveTheApplicationBelowIt() throws {
        let (_, _, collectionView) = try makeSUT()
        let header = IndexPath(item: 0, section: 1)
        let kind = UICollectionView.elementKindSectionHeader
        let before = try XCTUnwrap(collectionView.layoutAttributesForSupplementaryElement(ofKind: kind, at: header)).frame

        scroll(collectionView, toScreenshot: screenshotsPerApp - 1, ofApp: 0)

        let after = try XCTUnwrap(collectionView.layoutAttributesForSupplementaryElement(ofKind: kind, at: header)).frame
        XCTAssertEqual(after, before)
    }

    // MARK: - Width changes (rotation, Split View, iPad)

    func testTilesAreMeasuredAgainWhenTheWidthChanges() throws {
        let (sut, _, collectionView) = try makeSUT(width: 390)
        let first = IndexPath(item: 0, section: 0)

        for width in [CGFloat(390), 820, 1032, 390] {
            sut.view.frame.size.width = width
            sut.view.layoutIfNeeded()

            let metrics = GalleryMetrics(containerWidth: width)
            let attributes = try XCTUnwrap(collectionView.layoutAttributesForItem(at: first))
            XCTAssertEqual(attributes.frame.size, metrics.tileSize, "width \(width)")
        }
    }

    func testAWiderContainerShowsMoreTilesOfTheSameGallery() throws {
        let (sut, _, collectionView) = try makeSUT(width: 390)
        let narrowCount = visibleItems(ofApp: 0, in: collectionView).count

        sut.view.frame.size.width = 1032
        sut.view.layoutIfNeeded()

        XCTAssertGreaterThan(visibleItems(ofApp: 0, in: collectionView).count, narrowCount)
    }
}
