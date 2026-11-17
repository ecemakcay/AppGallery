import SnapKit
import UIKit

/// One page of the preview: a single screenshot, large.
///
/// A plain view controller on purpose: it has no business logic, so an interactor and a presenter
/// would have nothing to do. It reads its image from the same download manager as the list.
final class PreviewPageViewController: UIViewController {

    private enum Layout {
        static let contentInset: CGFloat = 24
        static let failureSpacing: CGFloat = 16
    }

    let url: URL
    /// Where this screenshot is in its application's gallery. The preview uses it to find the neighbors.
    let index: Int
    private let images: any ImageProviding

    /// Listens for finished downloads. Readable so that tests can wait for it to end.
    private(set) var imageUpdatesTask: Task<Void, Never>?

    /// What the page shows, readable for tests.
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

    init(url: URL, index: Int, images: any ImageProviding) {
        self.url = url
        self.index = index
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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        retryButton.addAction(UIAction { [weak self] _ in self?.retry() }, for: .touchUpInside)
        observeImageUpdates()
        showCurrentState()
    }

    /// The request is made when the page is about to be seen, not when it is created: the page
    /// controller may prepare a page that the user never swipes to.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The user is waiting for this one image, so it goes to the front of the queue.
        // If it is cached or already downloading, this does nothing.
        images.request(url, priority: .high)
        showCurrentState()
    }

    // MARK: - Setup

    private func setupViews() {
        // Black in both appearances. The preview around it is forced dark, so the semantic
        // colors of the failure text and the spinner resolve to their dark variants.
        view.backgroundColor = .black
        view.addSubview(imageView)
        view.addSubview(loadingIndicator)
        view.addSubview(failureStackView)
        failureStackView.addArrangedSubview(failureLabel)
        failureStackView.addArrangedSubview(retryButton)
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
    }

    // MARK: - Image

    /// `self` is only referred to weakly inside the loop, so this task never keeps the page alive.
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
