import UIKit

@MainActor
protocol SearchRoutingLogic: AnyObject {
    func routeToPreview()
}

@MainActor
protocol SearchDataPassing: AnyObject {
    var dataStore: (any SearchDataStore)? { get }
}

/// Opens the screens that follow the Search scene, and hands them the data they need.
@MainActor
final class SearchRouter: SearchRoutingLogic, SearchDataPassing {

    weak var viewController: UIViewController?
    var dataStore: (any SearchDataStore)?

    private let images: any ImageProviding

    init(images: any ImageProviding) {
        self.images = images
    }

    /// Presents the screenshot the interactor recorded as selected, full screen.
    ///
    /// The preview gets the same download manager as the list. If its image is not there yet, it asks
    /// that manager for it, so the limit of three concurrent downloads holds on this screen as well.
    func routeToPreview() {
        guard let url = dataStore?.selectedScreenshotURL else { return }

        let preview = PreviewViewController(url: url, images: images)
        preview.modalPresentationStyle = .fullScreen
        viewController?.present(preview, animated: true)
    }
}
