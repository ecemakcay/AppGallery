import SnapKit
import UIKit

/// One screenshot in the grid. For now it only shows its placeholder.
final class ScreenshotCell: UICollectionViewCell {

    static let reuseIdentifier = "ScreenshotCell"

    private enum Layout {
        static let cornerRadius: CGFloat = 12
        static let placeholderSize: CGFloat = 32
    }

    private let placeholderView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "photo"))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
    }

    /// The app has no storyboards or XIBs, so views are never decoded.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    private func setupViews() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = Layout.cornerRadius
        contentView.layer.masksToBounds = true
        contentView.addSubview(placeholderView)
    }

    private func setupConstraints() {
        placeholderView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(Layout.placeholderSize)
        }
    }
}
