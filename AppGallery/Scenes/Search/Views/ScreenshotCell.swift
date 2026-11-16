import SnapKit
import UIKit

/// One screenshot tile: the image, a spinner while it loads, or a retry icon if it failed.
final class ScreenshotCell: UICollectionViewCell {

    static let reuseIdentifier = "ScreenshotCell"

    enum State {
        case loading
        case image(UIImage)
        case failed
    }

    private enum Layout {
        static let retrySymbolPointSize: CGFloat = 24
    }

    /// The screenshot this cell shows right now. An update is matched against this URL and never
    /// against an index path, because the cell may have been reused for another screenshot since.
    private(set) var representedURL: URL?

    /// What the cell shows, readable for tests.
    var displayedImage: UIImage? {
        imageView.image
    }

    var showsRetryHint: Bool {
        !retryIconView.isHidden
    }

    var showsLoadingIndicator: Bool {
        loadingIndicator.isAnimating
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    /// Small on purpose: there is no other download progress anywhere in the interface.
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private let retryIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "arrow.clockwise"))
        imageView.tintColor = .secondaryLabel
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: Layout.retrySymbolPointSize)
        imageView.accessibilityLabel = "Retry"
        imageView.isAccessibilityElement = true
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
        show(.loading)
    }

    /// The app has no storyboards or XIBs, so views are never decoded.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Whatever this cell showed belongs to another screenshot.
        representedURL = nil
        show(.loading)
    }

    func configure(url: URL, state: State) {
        representedURL = url
        show(state)
    }

    private func show(_ state: State) {
        switch state {
        case .loading:
            imageView.image = nil
            retryIconView.isHidden = true
            loadingIndicator.startAnimating()
        case .image(let image):
            imageView.image = image
            retryIconView.isHidden = true
            loadingIndicator.stopAnimating()
        case .failed:
            imageView.image = nil
            retryIconView.isHidden = false
            loadingIndicator.stopAnimating()
        }
    }

    private func setupViews() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = GalleryMetrics.cornerRadius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true
        contentView.addSubview(imageView)
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(retryIconView)
    }

    private func setupConstraints() {
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        loadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        retryIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }
}
