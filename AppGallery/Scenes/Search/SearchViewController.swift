import UIKit

@MainActor
protocol SearchDisplayLogic: AnyObject {
    func displayApps(viewModel: Search.FetchApps.ViewModel)
}

final class SearchViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App Gallery"
        view.backgroundColor = .systemBackground
    }
}
