import SnapKit
import UIKit

/// Section header of one application: its name, its developer and how many screenshots it has.
final class AppSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "AppSectionHeaderView"
    /// Fixed, because every label is a single line that truncates.
    static let height: CGFloat = 60

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let topInset: CGFloat = 12
        static let labelSpacing: CGFloat = 2
        static let titleToCountSpacing: CGFloat = 8
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        return label
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        // A long title truncates; the count keeps its full width.
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
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

    func configure(with section: Search.AppSection) {
        titleLabel.text = section.title
        subtitleLabel.text = section.subtitle
        countLabel.text = section.screenshotCountText
    }

    private func setupViews() {
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(countLabel)
    }

    private func setupConstraints() {
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(Layout.topInset)
            make.leading.equalToSuperview().inset(Layout.horizontalInset)
        }
        countLabel.snp.makeConstraints { make in
            make.firstBaseline.equalTo(titleLabel)
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(Layout.titleToCountSpacing)
            make.trailing.equalToSuperview().inset(Layout.horizontalInset)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(Layout.labelSpacing)
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalInset)
        }
    }
}
