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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupConstraints()
        configureSearchController()
        configureCollectionView()
        configureActions()

        // An empty query makes the interactor present the idle state.
        interactor?.fetchApps(request: Search.FetchApps.Request(query: ""))
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
        collectionView.dequeueReusableCell(withReuseIdentifier: ScreenshotCell.reuseIdentifier, for: indexPath)
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
        CGSize(width: collectionView.bounds.width, height: AppSectionHeaderView.height)
    }
}
