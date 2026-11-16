import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Composition root: the app's long-lived dependencies are created here and injected.
        let worker = SearchWorker(apiClient: APIClient())
        let images = ImageDownloadManager(fetcher: URLSessionImageFetcher())
        let searchViewController = SearchConfigurator.makeScene(worker: worker, images: images)

        let navigationController = UINavigationController(rootViewController: searchViewController)
        navigationController.navigationBar.prefersLargeTitles = true

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }
}
