import SnapKit
import UIKit

@MainActor
protocol SearchDisplayLogic: AnyObject {
    func displayApps(viewModel: Search.FetchApps.ViewModel)
}

/// The search bar and the list of applications, each with a gallery of screenshots that scrolls
/// sideways. It forwards user input to the interactor and renders the view models it is given;
/// it holds no business logic.
final class SearchViewController: UIViewController {

    var interactor: (any SearchBusinessLogic)?
    var router: (any SearchRoutingLogic)?
    /// Read-only access to the screenshots. Scheduling them is the interactor's decision.
    var images: (any ImageProviding)?

    private enum Layout {
        /// Only estimates: the real heights come from the views' own constraints.
        static let estimatedHeaderHeight: CGFloat = 64
        static let estimatedSummaryHeight: CGFloat = 28
        static let sectionBottomSpacing: CGFloat = 20
    }

    private var summary = ""
    private var sections: [Search.AppSection] = []

    private let searchController = UISearchController(searchResultsController: nil)

    private let collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: SearchViewController.makeLayout()
    )

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

    // MARK: - Layout

    /// One section per application, and each section scrolls sideways on its own.
    ///
    /// It is still a single collection view with the same data source as a plain list:
    /// `orthogonalScrollingBehavior` is what turns a section into a horizontal gallery.
    /// UIKit calls the closure again whenever the width changes (rotation, Split View),
    /// so the tiles are always measured for the width that is available right now.
    private static func makeLayout() -> UICollectionViewLayout {
        let summary = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(Layout.estimatedSummaryHeight)
            ),
            elementKind: SearchSummaryView.elementKind,
            alignment: .top
        )
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.boundarySupplementaryItems = [summary]

        return UICollectionViewCompositionalLayout(sectionProvider: { _, environment in
            let metrics = GalleryMetrics(containerWidth: environment.container.effectiveContentSize.width)

            // Item: one tile. Group: the unit that repeats along the row, here a single tile.
            let tileSize = NSCollectionLayoutSize(
                widthDimension: .absolute(metrics.tileSize.width),
                heightDimension: .absolute(metrics.tileSize.height)
            )
            let item = NSCollectionLayoutItem(layoutSize: tileSize)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: tileSize, subitems: [item])

            // Section: one application. Every tile has the same size, so the height of a
            // section never changes while its gallery scrolls.
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = metrics.spacing
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: metrics.margin,
                bottom: Layout.sectionBottomSpacing,
                trailing: metrics.margin
            )
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .estimated(Layout.estimatedHeaderHeight)
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
            ]
            return section
        }, configuration: configuration)
    }

    // MARK: - Setup

    private func setupViews() {
        title = "AppGallery"
        navigationItem.largeTitleDisplayMode = .always
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
        searchController.searchBar.placeholder = "Search apps"
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
        collectionView.register(
            SearchSummaryView.self,
            forSupplementaryViewOfKind: SearchSummaryView.elementKind,
            withReuseIdentifier: SearchSummaryView.reuseIdentifier
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
        case .results(let summary, let sections):
            self.summary = summary
            self.sections = sections
            stateView.hide()
        case .loading:
            clearResults()
            stateView.showLoading()
        case .message(let message):
            clearResults()
            stateView.showMessage(message)
        case .error(let message):
            clearResults()
            stateView.showError(message)
        }
        collectionView.reloadData()
    }

    private func clearResults() {
        summary = ""
        sections = []
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
        // The summary belongs to the whole list; every other supplementary view is an application's header.
        if kind == SearchSummaryView.elementKind {
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: SearchSummaryView.reuseIdentifier,
                for: indexPath
            )
            (view as? SearchSummaryView)?.configure(text: summary)
            return view
        }

        let view = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: AppSectionHeaderView.reuseIdentifier,
            for: indexPath
        )
        if let header = view as? AppSectionHeaderView {
            header.configure(with: sections[indexPath.section], showsSeparator: indexPath.section > 0)
        }
        return view
    }
}

// MARK: - UICollectionViewDelegate

extension SearchViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let url = sections[indexPath.section].screenshotURLs[indexPath.item]
        if let images, images.hasFailed(url) {
            // Tapping a failed screenshot retries it, ahead of the downloads that are still waiting.
            images.request(url, priority: .high)
            refreshCells(showing: url)
            return
        }
        // Clean Swift routing: the interactor records what was selected in its data store,
        // and the router reads it from there when it builds the next screen.
        let request = Search.SelectScreenshot.Request(appIndex: indexPath.section, screenshotIndex: indexPath.item)
        interactor?.selectScreenshot(request: request)
        router?.routeToPreview()
    }
}
