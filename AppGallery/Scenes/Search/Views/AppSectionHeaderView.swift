import SnapKit
import UIKit

/// Section header of one application: its name, its developer and how many screenshots it has.
final class AppSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "AppSectionHeaderView"

    /// Every label is a single line, so the height follows from the fonts and grows with Dynamic Type.
    static var preferredHeight: CGFloat {
        let labelHeights = Font.title.lineHeight + Font.detail.lineHeight
        return (Layout.topInset + labelHeights + Layout.labelSpacing + Layout.bottomInset).rounded(.up)
    }

    private enum Layout {
        static let horizontalInset: CGFloat = 16
        static let topInset: CGFloat = 12
        static let bottomInset: CGFloat = 8
        static let labelSpacing: CGFloat = 2
        static let subtitleToCountSpacing: CGFloat = 8
    }

    /// Read on every use, because the preferred fonts change with the user's text size.
    private enum Font {
        static var title: UIFont { .preferredFont(forTextStyle: .headline) }
        static var detail: UIFont { .preferredFont(forTextStyle: .footnote) }
    }

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = Font.title
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = Font.detail
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = Font.detail
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        // A long developer name truncates; the count keeps its full width.
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
        // The name gets a full line of its own, so it stays readable at the largest text sizes.
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(Layout.topInset)
            make.leading.trailing.equalToSuperview().inset(Layout.horizontalInset)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(Layout.labelSpacing)
            make.leading.equalToSuperview().inset(Layout.horizontalInset)
        }
        countLabel.snp.makeConstraints { make in
            make.firstBaseline.equalTo(subtitleLabel)
            make.leading.greaterThanOrEqualTo(subtitleLabel.snp.trailing).offset(Layout.subtitleToCountSpacing)
            make.trailing.equalToSuperview().inset(Layout.horizontalInset)
        }
    }
}
