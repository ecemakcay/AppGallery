import SnapKit
import UIKit

/// Shows the screenshots of one application large, on a dark background. It opens on the screenshot
/// that was tapped; swiping left and right moves through the rest of that application's gallery.
///
/// A `UIPageViewController` does the paging: it creates a page only when the user swipes towards it,
/// keeps each page at full size through rotation and Split View, and supports VoiceOver's
/// three-finger swipe. Each page shows one screenshot (`PreviewPageViewController`).
///
/// It covers the whole screen, so the search bar cannot be reached while it is up. That is why the
/// query cannot change, and the downloads cannot be cancelled, underneath an open preview.
final class PreviewViewController: UIViewController {

    private enum Layout {
        static let controlInset: CGFloat = 8
        static let pageSpacing: CGFloat = 16
        static let counterFontSize: CGFloat = 15
        static let counterPadding = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    }

    private let urls: [URL]
    private let images: any ImageProviding

    /// Which screenshot is on screen. Readable for tests.
    private(set) var currentIndex: Int

    /// The page on screen.
    var currentPage: PreviewPageViewController? {
        pageViewController.viewControllers?.first as? PreviewPageViewController
    }

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: [.interPageSpacing: Layout.pageSpacing]
    )

    /// "3 / 8": where the user is in the gallery. Hidden when there is only one screenshot.
    private let counterLabel: UILabel = {
        let label = UILabel()
        // Digits of equal width, so the capsule does not change size from "1 / 8" to "2 / 8".
        let font = UIFont.monospacedDigitSystemFont(ofSize: Layout.counterFontSize, weight: .semibold)
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: font)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    /// A dimmed capsule behind the counter, so that it stays readable on top of a bright screenshot.
    private let counterBackground: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.8)
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let closeButton: UIButton = {
        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(systemName: "xmark")
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = "Close"
        return button
    }()

    /// `startIndex` must be a position in `urls`; the interactor only records selections that are.
    init(urls: [URL], startIndex: Int, images: any ImageProviding) {
        precondition(urls.indices.contains(startIndex), "The preview needs a screenshot to start on")
        self.urls = urls
        self.currentIndex = startIndex
        self.images = images
        super.init(nibName: nil, bundle: nil)
    }

    /// The app has no storyboards or XIBs, so view controllers are never decoded.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        pageViewController.dataSource = self
        pageViewController.delegate = self
        if let page = makePage(at: currentIndex) {
            pageViewController.setViewControllers([page], direction: .forward, animated: false)
        }
        updateCounter()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        counterBackground.layer.cornerRadius = counterBackground.bounds.height / 2
    }

    // MARK: - Setup

    private func setupViews() {
        // Dark in both appearances. The pages and the controls follow this, and so does the
        // status bar, which shows light text while the preview is up.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black

        // Standard containment: the page controller is a child, so it gets the appearance callbacks
        // and passes them on to its pages.
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)

        view.addSubview(counterBackground)
        counterBackground.addSubview(counterLabel)
        view.addSubview(closeButton)
    }

    private func setupConstraints() {
        pageViewController.view.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        closeButton.snp.makeConstraints { make in
            make.top.trailing.equalTo(view.safeAreaLayoutGuide).inset(Layout.controlInset)
        }
        counterBackground.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(closeButton)
        }
        counterLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(Layout.counterPadding)
        }
    }

    // MARK: - Pages

    private func makePage(at index: Int) -> PreviewPageViewController? {
        guard urls.indices.contains(index) else { return nil }
        return PreviewPageViewController(url: urls[index], index: index, images: images)
    }

    private func updateCounter() {
        counterBackground.isHidden = urls.count < 2
        counterLabel.text = "\(currentIndex + 1) / \(urls.count)"
        counterLabel.accessibilityLabel = "Screenshot \(currentIndex + 1) of \(urls.count)"
    }
}

// MARK: - UIPageViewControllerDataSource

extension PreviewViewController: UIPageViewControllerDataSource {

    /// `nil` at either end, so the first and the last screenshot do not wrap around.
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? PreviewPageViewController else { return nil }
        return makePage(at: page.index - 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let page = viewController as? PreviewPageViewController else { return nil }
        return makePage(at: page.index + 1)
    }
}

// MARK: - UIPageViewControllerDelegate

extension PreviewViewController: UIPageViewControllerDelegate {

    /// Called after a swipe. A swipe the user let go of halfway comes back with `completed == false`
    /// and leaves the counter as it was.
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let page = currentPage else { return }
        currentIndex = page.index
        updateCounter()
    }
}
