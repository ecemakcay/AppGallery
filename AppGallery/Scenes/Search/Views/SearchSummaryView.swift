import SnapKit
import UIKit

/// The line above the results: how many applications were found for which query.
final class SearchSummaryView: UICollectionReusableView {

    static let elementKind = "SearchSummary"
    static let reuseIdentifier = "SearchSummaryView"

    private enum Layout {
        static let verticalInset: CGFloat = 6
    }

    private let label: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        label.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(Layout.verticalInset)
            make.leading.trailing.equalTo(layoutMarginsGuide)
        }
    }

    /// The app has no storyboards or XIBs, so views are never decoded.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func configure(text: String) {
        label.text = text
    }

    /// This view spans the whole container, so it lines its text up with the galleries
    /// by taking the margin from the same metrics, for whatever width it has right now.
    override func layoutSubviews() {
        let margin = GalleryMetrics(containerWidth: bounds.width).margin
        let margins = NSDirectionalEdgeInsets(top: 0, leading: margin, bottom: 0, trailing: margin)
        if directionalLayoutMargins != margins {
            directionalLayoutMargins = margins
        }
        super.layoutSubviews()
    }
}
