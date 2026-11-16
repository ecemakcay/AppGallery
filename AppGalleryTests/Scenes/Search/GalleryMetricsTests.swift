import XCTest
@testable import AppGallery

final class GalleryMetricsTests: XCTestCase {

    // MARK: - The three widths of the design

    func testAnIPhoneShowsTwoAndAHalfTiles() {
        let metrics = GalleryMetrics(containerWidth: 390)

        XCTAssertEqual(metrics.visibleTileCount, 2.5)
        XCTAssertEqual(metrics.margin, 16)
        XCTAssertEqual(metrics.spacing, 10)
        XCTAssertEqual(metrics.tileSize, CGSize(width: 141, height: 251))
    }

    func testAnElevenInchIPadInPortraitShowsThreeAndAHalfTiles() {
        let metrics = GalleryMetrics(containerWidth: 820)

        XCTAssertEqual(metrics.visibleTileCount, 3.5)
        XCTAssertEqual(metrics.margin, 20)
        XCTAssertEqual(metrics.spacing, 12)
        XCTAssertEqual(metrics.tileSize, CGSize(width: 218, height: 388))
    }

    func testAThirteenInchIPadInPortraitShowsFourAndAHalfTiles() {
        let metrics = GalleryMetrics(containerWidth: 1032)

        XCTAssertEqual(metrics.visibleTileCount, 4.5)
        XCTAssertEqual(metrics.margin, 20)
        XCTAssertEqual(metrics.spacing, 14)
        XCTAssertEqual(metrics.tileSize, CGSize(width: 212, height: 377))
    }

    // MARK: - Rules

    func testTheTileCountFollowsTheWidthNotTheDevice() {
        // An iPad squeezed into a narrow Split View behaves like an iPhone;
        // an iPhone in landscape behaves like a medium iPad.
        XCTAssertEqual(GalleryMetrics(containerWidth: 599).visibleTileCount, 2.5)
        XCTAssertEqual(GalleryMetrics(containerWidth: 600).visibleTileCount, 3.5)
        XCTAssertEqual(GalleryMetrics(containerWidth: 899).visibleTileCount, 3.5)
        XCTAssertEqual(GalleryMetrics(containerWidth: 900).visibleTileCount, 4.5)
    }

    func testEveryTileIsNineBySixteen() {
        for width in stride(from: CGFloat(320), through: 1400, by: 37) {
            let size = GalleryMetrics(containerWidth: width).tileSize

            XCTAssertEqual(size.height, (size.width * 16 / 9).rounded(), "width \(width)")
        }
    }

    func testTheVisibleTilesAndTheirGapsFillTheRowUpToTheTrailingEdge() {
        for width in [CGFloat(390), 430, 744, 820, 1032, 1376] {
            let metrics = GalleryMetrics(containerWidth: width)
            let gaps = metrics.visibleTileCount.rounded(.down) * metrics.spacing
            let used = metrics.margin + metrics.visibleTileCount * metrics.tileSize.width + gaps

            // Rounding the tile width down may leave less than one point per visible tile unused.
            XCTAssertLessThanOrEqual(used, width)
            XCTAssertGreaterThan(used, width - metrics.visibleTileCount)
        }
    }

    func testAWidthOfZeroGivesAnEmptyTileInsteadOfANegativeOne() {
        XCTAssertEqual(GalleryMetrics(containerWidth: 0).tileSize, .zero)
    }
}
