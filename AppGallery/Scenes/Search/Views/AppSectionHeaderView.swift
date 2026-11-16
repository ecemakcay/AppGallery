import SnapKit
import UIKit

/// Header of one application: its name, and under it the developer and the number of screenshots.
///
/// Its height comes from its constraints (the layout only gives an estimate),
/// so it grows by itself when the user chooses a larger text size.
final class AppSectionHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "AppSectionHeaderView"

    private enum Layout {
        static let separatorHeight: CGFloat = 1
        /// The separator runs past the trailing margin to the edge of the screen; the collection view clips the rest.
        static let separatorOverflow: CGFloat = 40
        static let topInset: CGFloat = 14
        static let labelSpacing: CGFloat = 2
        static let bottomInset: CGFloat = 10
    }

    private let separatorView: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    /// Developer, dot and count. Side by side normally; one under the other at accessibility text sizes.
    private let detailStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.spacing = 0
        return stackView
    }()

    private let developerLabel: UILabel = {
        let label = AppSectionHeaderView.makeDetailLabel()
        // When there is not enough room, this is the label that gives way.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let dotLabel: UILabel = {
        let label = AppSectionHeaderView.makeDetailLabel()
        label.text = " · "
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let countLabel: UILabel = {
        let label = AppSectionHeaderView.makeDetailLabel()
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
        applyLayout(for: traitCollection.preferredContentSizeCategory)
    }

    /// The app has no storyboards or XIBs, so views are never decoded.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    /// - Parameter showsSeparator: `false` for the first application, which has nothing above it to be separated from.
    func configure(with section: Search.AppSection, showsSeparator: Bool) {
        titleLabel.text = section.title
        developerLabel.text = section.developer
        // A hidden label takes no room in the stack, so the count moves to the leading edge
        // and the header keeps its two-line height when the API names no developer.
        developerLabel.isHidden = section.developer.isEmpty
        countLabel.text = section.screenshotCountText
        separatorView.isHidden = !showsSeparator
        applyLayout(for: traitCollection.preferredContentSizeCategory)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            applyLayout(for: traitCollection.preferredContentSizeCategory)
        }
    }

    /// At the accessibility text sizes one line cannot hold both the developer and the count, so
    /// they go on separate lines and may wrap. Not `private`, so tests can try both arrangements.
    func applyLayout(for contentSizeCategory: UIContentSizeCategory) {
        let isStacked = contentSizeCategory.isAccessibilityCategory

        detailStackView.axis = isStacked ? .vertical : .horizontal
        detailStackView.alignment = isStacked ? .leading : .firstBaseline
        dotLabel.isHidden = isStacked || developerLabel.isHidden

        titleLabel.numberOfLines = isStacked ? 2 : 1
        developerLabel.numberOfLines = isStacked ? 0 : 1
        countLabel.numberOfLines = isStacked ? 0 : 1
        // On one line the count is never truncated; the developer gives way instead.
        // On a line of its own it may wrap, so it must be allowed to become narrower than its text.
        countLabel.setContentCompressionResistancePriority(isStacked ? .defaultHigh : .required, for: .horizontal)
    }

    private static func makeDetailLabel() -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        return label
    }

    private func setupViews() {
        addSubview(separatorView)
        addSubview(titleLabel)
        addSubview(detailStackView)
        detailStackView.addArrangedSubview(developerLabel)
        detailStackView.addArrangedSubview(dotLabel)
        detailStackView.addArrangedSubview(countLabel)
    }

    private func setupConstraints() {
        separatorView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
            make.trailing.equalToSuperview().offset(Layout.separatorOverflow)
            make.height.equalTo(Layout.separatorHeight)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(Layout.topInset)
            make.leading.trailing.equalToSuperview()
        }
        // The stack, not a single label, sets the height: it is right with or without a developer.
        detailStackView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(Layout.labelSpacing)
            make.leading.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
            make.bottom.equalToSuperview().inset(Layout.bottomInset)
        }
    }
}
