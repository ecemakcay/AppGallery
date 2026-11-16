import SnapKit
import UIKit

/// Shows one screenshot large, on a dark background.
///
/// A plain view controller on purpose: it has no business logic, so an interactor and a presenter
/// would have nothing to do. It reads its image from the same download manager as the list.
///
/// It covers the whole screen, so the search bar cannot be reached while it is up. That is why the
/// query cannot change, and the downloads cannot be cancelled, underneath an open preview.
final class PreviewViewController: UIViewController {

    private enum Layout {
        static let closeButtonInset: CGFloat = 8
        static let contentInset: CGFloat = 24
        static let failureSpacing: CGFloat = 16
    }

    private let url: URL
    private let images: any ImageProviding

    /// Listens for finished downloads. Readable so that tests can wait for it to end.
    private(set) var imageUpdatesTask: Task<Void, Never>?

    /// What the screen shows, readable for tests.
    var displayedImage: UIImage? {
        imageView.image
    }

    var showsLoadingIndicator: Bool {
        loadingIndicator.isAnimating
    }

    var showsFailure: Bool {
        !failureStackView.isHidden
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private let failureStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = Layout.failureSpacing
        return stackView
    }()

    private let failureLabel: UILabel = {
        let label = UILabel()
        label.text = "This screenshot could not be loaded."
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let retryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Retry"
        return UIButton(configuration: configuration)
    }()

    private let closeButton: UIButton = {
        var configuration = UIButton.Configuration.gray()
        configuration.image = UIImage(systemName: "xmark")
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = "Close"
        return button
    }()

    init(url: URL, images: any ImageProviding) {
        self.url = url
        self.images = images
        super.init(nibName: nil, bundle: nil)
    }

    /// The app has no storyboards or XIBs, so view controllers are never decoded.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        imageUpdatesTask?.cancel()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        configureActions()
        observeImageUpdates()

        // The user is waiting for this one image, so it goes to the front of the queue.
        // If it is cached or already downloading, this does nothing.
        images.request(url, priority: .high)
        showCurrentState()
    }

    // MARK: - Setup

    private func setupViews() {
        // The preview is dark in both appearances; the semantic colors below follow this.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        view.addSubview(imageView)
        view.addSubview(loadingIndicator)
        view.addSubview(failureStackView)
        failureStackView.addArrangedSubview(failureLabel)
        failureStackView.addArrangedSubview(retryButton)
        view.addSubview(closeButton)
    }

    private func setupConstraints() {
        imageView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        loadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        failureStackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(Layout.contentInset)
            make.trailing.lessThanOrEqualToSuperview().inset(Layout.contentInset)
        }
        closeButton.snp.makeConstraints { make in
            make.top.trailing.equalTo(view.safeAreaLayoutGuide).inset(Layout.closeButtonInset)
        }
    }

    private func configureActions() {
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        retryButton.addAction(UIAction { [weak self] _ in self?.retry() }, for: .touchUpInside)
    }

    // MARK: - Image

    /// `self` is only referred to weakly inside the loop, so this task never keeps the preview alive.
    private func observeImageUpdates() {
        let updates = images.updates()
        imageUpdatesTask = Task { [weak self, url] in
            for await updatedURL in updates where updatedURL == url {
                self?.showCurrentState()
            }
        }
    }

    private func retry() {
        images.request(url, priority: .high)
        showCurrentState()
    }

    private func showCurrentState() {
        if let image = images.image(for: url) {
            imageView.image = image
            loadingIndicator.stopAnimating()
            failureStackView.isHidden = true
        } else if images.hasFailed(url) {
            imageView.image = nil
            loadingIndicator.stopAnimating()
            failureStackView.isHidden = false
        } else {
            imageView.image = nil
            loadingIndicator.startAnimating()
            failureStackView.isHidden = true
        }
    }
}
