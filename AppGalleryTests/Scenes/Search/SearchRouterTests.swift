import XCTest
@testable import AppGallery

/// Presenting needs a view controller that is on screen, so these tests put one into a window.
@MainActor
final class SearchRouterTests: XCTestCase {

    private var window: UIWindow?

    override func tearDown() async throws {
        window?.rootViewController?.dismiss(animated: false)
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func makeSUT(selected url: URL?) -> (sut: SearchRouter, source: UIViewController, images: ImageProvidingStub) {
        let source = UIViewController()
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = source
        window.isHidden = false
        self.window = window

        let dataStore = SearchDataStoreStub()
        dataStore.selectedScreenshotURL = url
        let images = ImageProvidingStub()
        let sut = SearchRouter(images: images)
        sut.viewController = source
        sut.dataStore = dataStore
        return (sut, source, images)
    }

    func testRouteToPreviewPresentsTheSelectedScreenshotFullScreen() throws {
        let url = URL(fileURLWithPath: "/screenshots/1.png")
        let (sut, source, images) = makeSUT(selected: url)

        sut.routeToPreview()

        let preview = try XCTUnwrap(source.presentedViewController as? PreviewViewController)
        XCTAssertEqual(preview.modalPresentationStyle, .fullScreen)
        // The preview uses the same image source as the list: its request arrives at the router's stub.
        preview.loadViewIfNeeded()
        XCTAssertEqual(images.requests, [.init(url: url, priority: .high)])
    }

    func testRouteToPreviewDoesNothingWhenNoScreenshotIsSelected() {
        let (sut, source, _) = makeSUT(selected: nil)

        sut.routeToPreview()

        XCTAssertNil(source.presentedViewController)
    }
}
