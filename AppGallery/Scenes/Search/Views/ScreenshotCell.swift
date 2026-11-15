import SnapKit
import UIKit

/// One screenshot in the grid: the image, a placeholder while it loads, or a retry hint if it failed.
final class ScreenshotCell: UICollectionViewCell {

    static let reuseIdentifier = "ScreenshotCell"

    enum State {
        case loading
        case image(UIImage)
        case failed
    }

    private enum Layout {
        static let cornerRadius: CGFloat = 12
        static let statusSpacing: CGFloat = 6
        static let statusInset: CGFloat = 8
        static let symbolPointSize: CGFloat = 28
    }

    /// The screenshot this cell shows right now. An update is matched against this URL and never
    /// against an index path, because the cell may have been reused for another screenshot since.
    private(set) var representedURL: URL?

    /// What the cell shows, readable for tests.
    var displayedImage: UIImage? {
        imageView.image
    }

    var showsRetryHint: Bool {
        !statusStackView.isHidden && !statusLabel.isHidden
    }

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let statusStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = Layout.statusSpacing
        return stackView
    }()

    private let statusSymbolView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .tertiaryLabel
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: Layout.symbolPointSize)
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap to retry"
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
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
            statusSymbolView.image = UIImage(systemName: "photo")
            statusLabel.isHidden = true
            statusStackView.isHidden = false
        case .image(let image):
            imageView.image = image
            statusStackView.isHidden = true
        case .failed:
            imageView.image = nil
            statusSymbolView.image = UIImage(systemName: "arrow.clockwise")
            statusLabel.isHidden = false
            statusStackView.isHidden = false
        }
    }

    private func setupViews() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = Layout.cornerRadius
        contentView.layer.masksToBounds = true
        contentView.addSubview(imageView)
        contentView.addSubview(statusStackView)
        statusStackView.addArrangedSubview(statusSymbolView)
        statusStackView.addArrangedSubview(statusLabel)
    }

    private func setupConstraints() {
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        statusStackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(Layout.statusInset)
            make.trailing.lessThanOrEqualToSuperview().inset(Layout.statusInset)
        }
    }
}
