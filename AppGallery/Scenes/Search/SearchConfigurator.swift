import UIKit

/// Wires the Search scene. Dependencies come from outside, so tests can replace them.
///
/// Ownership: ViewController -> Interactor -> Presenter, and the Presenter refers back
/// to the ViewController weakly, so the scene is released with its view controller.
@MainActor
enum SearchConfigurator {

    static func makeScene(worker: any SearchWorkingLogic) -> SearchViewController {
        let viewController = SearchViewController()
        let presenter = SearchPresenter()
        let interactor = SearchInteractor(presenter: presenter, worker: worker)

        presenter.viewController = viewController
        viewController.interactor = interactor
        return viewController
    }
}
