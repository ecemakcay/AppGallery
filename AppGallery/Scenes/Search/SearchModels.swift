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
            case loaded(query: String, apps: [AppResult])
            case failed(any Error)
        }

        /// What the view controller shows, in display terms.
        enum ViewModel: Equatable {
            /// A centered text: the idle hint or "no results".
            case message(String)
            case loading
            /// `summary` is the line above the list, such as: 24 results for “weather”.
            case results(summary: String, sections: [AppSection])
            /// A centered text with a Retry button.
            case error(message: String)
        }
    }

    /// Use case: the user taps a screenshot to see it large.
    enum SelectScreenshot {

        struct Request {
            let appIndex: Int
            let screenshotIndex: Int
        }

        /// What the interactor records for the router: the whole gallery of the tapped application,
        /// so the preview can page through it, and where in it the tapped screenshot is.
        struct Selection: Equatable {
            let screenshotURLs: [URL]
            let index: Int
        }
    }

    /// One application, displayed as a collection view section.
    struct AppSection: Equatable {
        let title: String
        /// Empty when the API did not name a developer.
        let developer: String
        /// For example "8 screenshots". The header decides how it is placed next to the developer.
        let screenshotCountText: String
        let screenshotURLs: [URL]
    }
}
