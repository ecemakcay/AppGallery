import Foundation

@MainActor
protocol SearchPresentationLogic: AnyObject {
    func presentApps(response: Search.FetchApps.Response)
}

/// Turns the interactor's results into the texts and sections the view shows. No I/O and no UIKit.
@MainActor
final class SearchPresenter: SearchPresentationLogic {

    weak var viewController: (any SearchDisplayLogic)?

    func presentApps(response: Search.FetchApps.Response) {
        viewController?.displayApps(viewModel: makeViewModel(for: response))
    }

    // MARK: - Mapping

    private func makeViewModel(for response: Search.FetchApps.Response) -> Search.FetchApps.ViewModel {
        switch response {
        case .idle:
            return .message("Search for an application to see its screenshots.")
        case .loading:
            return .loading
        case .loaded(let apps) where apps.isEmpty:
            return .message("No applications found.")
        case .loaded(let apps):
            return .results(apps.map(makeSection))
        case .failed(let error):
            return .error(message: message(for: error))
        }
    }

    private func makeSection(for app: AppResult) -> Search.AppSection {
        Search.AppSection(
            title: app.name ?? "Unknown application",
            subtitle: app.developer ?? "",
            screenshotCountText: screenshotCountText(for: app.screenshotURLs.count),
            screenshotURLs: app.screenshotURLs
        )
    }

    private func screenshotCountText(for count: Int) -> String {
        switch count {
        case 0: return "No screenshots"
        case 1: return "1 screenshot"
        default: return "\(count) screenshots"
        }
    }

    /// Technical errors are never shown as they are.
    private func message(for error: any Error) -> String {
        switch error as? NetworkError {
        case .offline:
            return "No internet connection. Check your connection and try again."
        case .rateLimited:
            return "Too many requests. Please try again in a moment."
        default:
            return "Something went wrong. Please try again."
        }
    }
}
