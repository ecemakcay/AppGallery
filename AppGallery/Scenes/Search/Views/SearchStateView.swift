import SnapKit
import UIKit

/// Shown instead of the grid whenever there are no results on screen:
/// a spinner, a text, or a text with a Retry button.
final class SearchStateView: UIView {

    var onRetry: (() -> Void)?

    private enum Layout {
        static let spacing: CGFloat = 16
        static let horizontalInset: CGFloat = 32
    }

    private let stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = Layout.spacing
        return stackView
    }()

    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private let messageLabel: UILabel = {
        let label = UILabel()
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
        configureActions()
    }

    /// The app has no storyboards or XIBs, so views are never decoded.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: - States

    func showLoading() {
        show(isLoading: true, message: nil, showsRetry: false)
    }

    func showMessage(_ message: String) {
        show(isLoading: false, message: message, showsRetry: false)
    }

    func showError(_ message: String) {
        show(isLoading: false, message: message, showsRetry: true)
    }

    func hide() {
        activityIndicator.stopAnimating()
        isHidden = true
    }

    private func show(isLoading: Bool, message: String?, showsRetry: Bool) {
        isHidden = false
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        messageLabel.text = message
        messageLabel.isHidden = message == nil
        retryButton.isHidden = !showsRetry
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(stackView)
        stackView.addArrangedSubview(activityIndicator)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(retryButton)
    }

    private func setupConstraints() {
        stackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().inset(Layout.horizontalInset)
            make.trailing.lessThanOrEqualToSuperview().inset(Layout.horizontalInset)
        }
    }

    private func configureActions() {
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
    }
}
