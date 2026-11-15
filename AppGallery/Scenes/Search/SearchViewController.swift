import SnapKit
import UIKit

@MainActor
protocol SearchDisplayLogic: AnyObject {
    func displayApps(viewModel: Search.FetchApps.ViewModel)
}

/// The search bar and the grid of screenshots. It forwards user input to the interactor
/// and renders the view models it is given; it holds no business logic.
final class SearchViewController: UIViewController {

    var interactor: (any SearchBusinessLogic)?
    /// Read-only access to the screenshots. Scheduling them is the interactor's decision.
    var images: (any ImageProviding)?

    private enum Layout {
        static let columns: CGFloat = 2
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 16
        static let sectionBottomInset: CGFloat = 24
        /// Height over width of a portrait phone screenshot (the API returns 392x696 images).
        static let screenshotAspectRatio: CGFloat = 16.0 / 9.0
    }

    private var sections: [Search.AppSection] = []

    private let searchController = UISearchController(searchResultsController: nil)

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Layout.spacing
        layout.minimumLineSpacing = Layout.spacing
        layout.sectionInset = UIEdgeInsets(
            top: 0,
            left: Layout.horizontalInset,
            bottom: Layout.sectionBottomInset,
            right: Layout.horizontalInset
        )
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private let stateView = SearchStateView()

    /// Listens for finished downloads. Readable so that tests can wait for it to end.
    private(set) var imageUpdatesTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        configureSearchController()
        configureCollectionView()
        configureActions()
        observeImageUpdates()

        // An empty query makes the interactor present the idle state.
        interactor?.fetchApps(request: Search.FetchApps.Request(query: ""))
    }

    deinit {
        imageUpdatesTask?.cancel()
    }

    // MARK: - Setup

    private func setupViews() {
        title = "App Gallery"
        view.backgroundColor = .systemBackground
        view.addSubview(collectionView)
        view.addSubview(stateView)
    }

    private func setupConstraints() {
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        // Centered in the area that stays visible while the keyboard is up.
        stateView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
    }

    private func configureSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search applications"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        // Keeps the search bar under the title on every iOS version.
        navigationItem.preferredSearchBarPlacement = .stacked
        definesPresentationContext = true
    }

    private func configureCollectionView() {
        collectionView.backgroundColor = .systemBackground
        collectionView.keyboardDismissMode = .onDrag
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ScreenshotCell.self, forCellWithReuseIdentifier: ScreenshotCell.reuseIdentifier)
        collectionView.register(
            AppSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: AppSectionHeaderView.reuseIdentifier
        )
    }

    private func configureActions() {
        stateView.onRetry = { [weak self] in
            self?.interactor?.retryLastQuery()
        }
    }

    // MARK: - Images

    /// Listens for finished downloads for as long as this view controller lives.
    ///
    /// `self` is only referred to weakly inside the loop. A strong reference would keep the view
    /// controller alive for as long as the stream lasts, and `deinit` would never cancel the task.
    private func observeImageUpdates() {
        guard let updates = images?.updates() else { return }
        imageUpdatesTask = Task { [weak self] in
            for await url in updates {
                self?.refreshCells(showing: url)
            }
        }
    }

    /// Updates the visible cells that show `url` right now. Cells are found by the URL they
    /// represent, never by an index path remembered from before the download.
    private func refreshCells(showing url: URL) {
        for case let cell as ScreenshotCell in collectionView.visibleCells where cell.representedURL == url {
            configure(cell, with: url)
        }
    }

    private func configure(_ cell: ScreenshotCell, with url: URL) {
        if let image = images?.image(for: url) {
            cell.configure(url: url, state: .image(image))
        } else if images?.hasFailed(url) == true {
            cell.configure(url: url, state: .failed)
        } else {
            // Does nothing while the download is queued or running. It matters when the cache
            // has dropped an image that was downloaded earlier: this queues it again.
            images?.request(url, priority: .normal)
            cell.configure(url: url, state: .loading)
        }
    }
}

// MARK: - SearchDisplayLogic

extension SearchViewController: SearchDisplayLogic {

    func displayApps(viewModel: Search.FetchApps.ViewModel) {
        switch viewModel {
        case .results(let sections):
            self.sections = sections
            stateView.hide()
        case .loading:
            sections = []
            stateView.showLoading()
        case .message(let message):
            sections = []
            stateView.showMessage(message)
        case .error(let message):
            sections = []
            stateView.showError(message)
        }
        collectionView.reloadData()
    }
}

// MARK: - UISearchResultsUpdating

extension SearchViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        interactor?.fetchApps(request: Search.FetchApps.Request(query: query))
    }
}

// MARK: - UICollectionViewDataSource

extension SearchViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].screenshotURLs.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ScreenshotCell.reuseIdentifier,
            for: indexPath
        )
        if let screenshotCell = cell as? ScreenshotCell {
            configure(screenshotCell, with: sections[indexPath.section].screenshotURLs[indexPath.item])
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: AppSectionHeaderView.reuseIdentifier,
            for: indexPath
        )
        if let header = view as? AppSectionHeaderView {
            header.configure(with: sections[indexPath.section])
        }
        return view
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension SearchViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let url = sections[indexPath.section].screenshotURLs[indexPath.item]
        guard let images, images.hasFailed(url) else { return }
        // Tapping a failed screenshot retries it, ahead of the downloads that are still waiting.
        images.request(url, priority: .high)
        refreshCells(showing: url)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let totalSpacing = Layout.horizontalInset * 2 + Layout.spacing * (Layout.columns - 1)
        let width = max(0, ((collectionView.bounds.width - totalSpacing) / Layout.columns).rounded(.down))
        return CGSize(width: width, height: (width * Layout.screenshotAspectRatio).rounded(.down))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: AppSectionHeaderView.preferredHeight)
    }
}
