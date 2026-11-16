import XCTest
@testable import AppGallery

@MainActor
final class AppSectionHeaderViewTests: XCTestCase {

    private let regular = UIContentSizeCategory.large
    private let accessibility = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    /// Keeps the window of the hosted tests alive until the test ends.
    private var window: UIWindow?

    override func tearDown() async throws {
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func makeHeader(
        developer: String = "Developer",
        count: String = "8 screenshots",
        category: UIContentSizeCategory = .large
    ) -> AppSectionHeaderView {
        let header = AppSectionHeaderView()
        let section = Search.AppSection(title: "App", developer: developer, screenshotCountText: count, screenshotURLs: [])
        header.configure(with: section, showsSeparator: true)
        header.applyLayout(for: category)
        return header
    }

    /// The size the collection view gives the header: the width is fixed, the height is whatever the constraints need.
    private func fittingSize(of header: AppSectionHeaderView, width: CGFloat = 358) -> CGSize {
        header.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
    }

    private func dotIsVisible(in header: AppSectionHeaderView) throws -> Bool {
        let dot = try XCTUnwrap(header.descendants(ofType: UILabel.self).first { $0.text == " · " })
        return !dot.isHidden
    }

    // MARK: - Regular text sizes

    func testDeveloperAndCountShareOneLineSeparatedByADot() throws {
        let header = makeHeader()

        XCTAssertTrue(try dotIsVisible(in: header))
    }

    func testWithoutADeveloperThereIsNoDotAndTheHeightStaysTheSame() throws {
        let withDeveloper = makeHeader(developer: "Developer")
        let withoutDeveloper = makeHeader(developer: "")

        XCTAssertFalse(try dotIsVisible(in: withoutDeveloper))
        XCTAssertEqual(fittingSize(of: withoutDeveloper).height, fittingSize(of: withDeveloper).height)
    }

    func testAVeryLongDeveloperIsTruncatedInsteadOfMakingTheHeaderWiderOrTaller() {
        let short = makeHeader(developer: "Developer")
        let long = makeHeader(developer: String(repeating: "Very Long Developer Name ", count: 12))

        let size = fittingSize(of: long, width: 200)

        XCTAssertEqual(size.width, 200)
        XCTAssertEqual(size.height, fittingSize(of: short, width: 200).height)
    }

    // MARK: - Accessibility text sizes

    func testAccessibilitySizesPutDeveloperAndCountOnSeparateLines() throws {
        let sideBySide = makeHeader(category: regular)
        let stacked = makeHeader(category: accessibility)

        XCTAssertFalse(try dotIsVisible(in: stacked))
        XCTAssertGreaterThan(fittingSize(of: stacked).height, fittingSize(of: sideBySide).height)
    }

    func testAtAccessibilitySizesLongTextsWrapInsteadOfLeavingTheHeader() {
        let count = "1234 screenshots of every single screen"
        let wide = makeHeader(count: count, category: accessibility)
        let narrow = makeHeader(count: count, category: accessibility)

        let narrowSize = fittingSize(of: narrow, width: 120)

        // The count does not fit in 120 pt on one line. It may not push the header wider; it wraps.
        XCTAssertEqual(narrowSize.width, 120)
        XCTAssertGreaterThan(narrowSize.height, fittingSize(of: wide, width: 1000).height)
    }

    func testGoingBackToARegularSizeRestoresTheSingleLine() throws {
        let header = makeHeader(category: accessibility)
        let stackedHeight = fittingSize(of: header).height

        header.applyLayout(for: regular)

        XCTAssertTrue(try dotIsVisible(in: header))
        XCTAssertLessThan(fittingSize(of: header).height, stackedHeight)
    }

    // MARK: - Real Dynamic Type

    // The tests above switch the arrangement by hand and keep the regular fonts. These put the header
    // into a window whose traits carry the text size, so the fonts really grow and the header has to
    // notice the change by itself, through `traitCollectionDidChange`.

    /// A view controller in a window that tells its views the user chose `category`.
    private func makeHost(category: UIContentSizeCategory) throws -> UIViewController {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("Overriding the content size category of a view controller needs iOS 17.")
        }
        let host = UIViewController()
        host.traitOverrides.preferredContentSizeCategory = category

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        host.view.layoutIfNeeded()
        return host
    }

    /// Adds a realistic header to `host`, gives it the size the collection view would, and lays it out.
    private func installHeader(in host: UIViewController, width: CGFloat) -> AppSectionHeaderView {
        let header = AppSectionHeaderView()
        let section = Search.AppSection(
            title: "AccuWeather Weather Forecast",
            developer: "AccuWeather International, Inc.",
            screenshotCountText: "10 screenshots",
            screenshotURLs: []
        )
        host.view.addSubview(header)
        header.configure(with: section, showsSeparator: true)
        host.view.layoutIfNeeded()

        header.frame = CGRect(origin: .zero, size: fittingSize(of: header, width: width))
        header.layoutIfNeeded()
        return header
    }

    private func visibleLabels(in header: AppSectionHeaderView) -> [UILabel] {
        header.descendants(ofType: UILabel.self).filter { !$0.isHidden && !($0.text ?? "").isEmpty }
    }

    func testWithTheLargestTextSizeTheFontsGrowAndEveryLabelStaysInsideTheHeader() throws {
        let host = try makeHost(category: accessibility)

        for width in [CGFloat(358), 288] {
            let header = installHeader(in: host, width: width)

            XCTAssertEqual(header.traitCollection.preferredContentSizeCategory, accessibility)
            XCTAssertFalse(try dotIsVisible(in: header), "The header switched to the stacked arrangement by itself")

            let regularTitleSize = UIFont.preferredFont(
                forTextStyle: .headline,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: regular)
            ).pointSize
            let labels = visibleLabels(in: header)
            XCTAssertEqual(labels.count, 3, "Title, developer and count")
            XCTAssertGreaterThan(try XCTUnwrap(labels.first).font.pointSize, regularTitleSize * 1.5)

            for label in labels {
                let frame = label.convert(label.bounds, to: header)
                XCTAssertTrue(header.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(label.text ?? "") at width \(width)")
                // Tall enough for all of its lines: nothing is cut off at the bottom.
                let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                if label.numberOfLines == 0 {
                    XCTAssertLessThanOrEqual(needed.height, label.bounds.height + 0.5, "\(label.text ?? "") at width \(width)")
                }
            }
            header.removeFromSuperview()
        }
    }

    func testWithARegularTextSizeTheHostedHeaderKeepsOneDetailLine() throws {
        let host = try makeHost(category: regular)

        let header = installHeader(in: host, width: 358)

        XCTAssertEqual(header.traitCollection.preferredContentSizeCategory, regular)
        XCTAssertTrue(try dotIsVisible(in: header))
        for label in visibleLabels(in: header) {
            XCTAssertTrue(header.bounds.insetBy(dx: -0.5, dy: -0.5).contains(label.convert(label.bounds, to: header)))
        }
    }

    func testChangingTheTextSizeWhileOnScreenSwitchesTheArrangement() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("Overriding the content size category of a view controller needs iOS 17.")
        }
        let host = try makeHost(category: regular)
        let header = installHeader(in: host, width: 358)
        let regularHeight = fittingSize(of: header).height

        // The change is made on the view controller, so that is where the update has to start.
        host.traitOverrides.preferredContentSizeCategory = accessibility
        host.updateTraitsIfNeeded()

        XCTAssertFalse(try dotIsVisible(in: header))
        XCTAssertGreaterThan(fittingSize(of: header).height, regularHeight * 2)

        host.traitOverrides.preferredContentSizeCategory = regular
        host.updateTraitsIfNeeded()

        XCTAssertTrue(try dotIsVisible(in: header))
        XCTAssertEqual(fittingSize(of: header).height, regularHeight)
    }
}
