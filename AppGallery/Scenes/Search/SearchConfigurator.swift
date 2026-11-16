import UIKit

/// Wires the Search scene. Dependencies come from outside, so tests can replace them.
///
/// Ownership: ViewController -> Interactor -> Presenter, and ViewController -> Router. The Presenter
/// and the Router refer back to the ViewController weakly, so the scene is released with it.
@MainActor
enum SearchConfigurator {

    /// - Parameter debounce: How long the scene waits after the last keystroke; tests pass `.zero`.
    static func makeScene(
        worker: any SearchWorkingLogic,
        images: any ImageProviding & ImageDownloading,
        debounce: Duration = .milliseconds(350)
    ) -> SearchViewController {
        let viewController = SearchViewController()
        let presenter = SearchPresenter()
        let interactor = SearchInteractor(
            presenter: presenter,
            worker: worker,
            imageDownloader: images,
            debounce: debounce
        )

        let router = SearchRouter(images: images)

        presenter.viewController = viewController
        router.viewController = viewController
        router.dataStore = interactor
        viewController.interactor = interactor
        viewController.router = router
        viewController.images = images
        return viewController
    }
}
