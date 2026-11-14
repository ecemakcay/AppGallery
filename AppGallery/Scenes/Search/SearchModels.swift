import Foundation

/// Request, Response and ViewModel types of the Search scene, grouped per use case.
enum Search {

    /// Use case: the user edits the query, or retries the last one.
    enum FetchApps {

        struct Request {
            let query: String
        }

        /// What the interactor found out, in business terms.
        enum Response {
            /// The query is too short to search for.
            case idle
            /// A search for the current query is pending.
            case loading
            case loaded([AppResult])
            case failed(any Error)
        }

        /// What the view controller shows, in display terms.
        enum ViewModel: Equatable {
            /// A centered text: the idle hint or "no results".
            case message(String)
            case loading
            case results([AppSection])
            /// A centered text with a Retry button.
            case error(message: String)
        }
    }

    /// One application, displayed as a collection view section.
    struct AppSection: Equatable {
        let title: String
        let subtitle: String
        let screenshotCountText: String
        let screenshotURLs: [URL]
    }
}
