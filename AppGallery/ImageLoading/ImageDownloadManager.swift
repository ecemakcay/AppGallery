import os
import UIKit

enum ImagePriority {
    /// Joins the end of the queue.
    case normal
    /// Goes to the front of the queue: the user is waiting for this image.
    case high
}

/// What a view needs: read images, ask for one, and hear when one is ready.
@MainActor
protocol ImageProviding: AnyObject {
    /// The image if it is in memory. Synchronous, so a cell can show it without a placeholder flash.
    func image(for url: URL) -> UIImage?
    func hasFailed(_ url: URL) -> Bool
    /// Makes sure `url` gets downloaded. Safe to call repeatedly.
    func request(_ url: URL, priority: ImagePriority)
    /// The URLs whose download ended, successfully or not, from now on.
    func updates() -> AsyncStream<URL>
}

/// What the interactor needs: schedule the screenshots of a search, and drop them again.
@MainActor
protocol ImageDownloading: AnyObject {
    func enqueue(_ urls: [URL])
    func cancelAll()
}

/// Downloads images with at most `maxConcurrentDownloads` requests in flight, app-wide.
///
/// `@MainActor` instead of an `actor` of its own: the state below is small bookkeeping, while the
/// slow work (network and decoding) happens off the main thread inside the fetcher. In return,
/// cells read the cache synchronously, and the state needs no locks.
@MainActor
final class ImageDownloadManager: ImageProviding, ImageDownloading {

    /// Roughly 180 screenshots of 392x696 pixels. `NSCache` treats it as a hint, not a hard limit.
    static let defaultCacheCostLimit = 200 * 1024 * 1024

    private struct Download {
        let id: Int
        let task: Task<Void, Never>
    }

    private let fetcher: any ImageFetching
    private let maxConcurrentDownloads: Int
    private let cache = NSCache<NSURL, UIImage>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppGallery", category: "ImageDownloads")

    /// Waiting for a free slot, first in line first.
    private var pending: [URL] = []
    /// The download that currently counts for each URL. Used to avoid duplicate downloads
    /// and to recognize completions that are no longer wanted.
    private var current: [URL: Download] = [:]
    /// Slots in use. Kept apart from `current` on purpose: `cancelAll()` empties `current` at once,
    /// but a cancelled download holds its slot until its task has really returned.
    private var occupiedSlots = 0
    private var failed: Set<URL> = []
    private var lastDownloadID = 0
    private var subscribers: [UUID: AsyncStream<URL>.Continuation] = [:]

    init(
        fetcher: any ImageFetching,
        maxConcurrentDownloads: Int = 3,
        cacheCostLimit: Int = ImageDownloadManager.defaultCacheCostLimit
    ) {
        self.fetcher = fetcher
        // A limit below 1 would leave every download waiting forever.
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        cache.totalCostLimit = cacheCostLimit
    }

    // MARK: - ImageDownloading

    func enqueue(_ urls: [URL]) {
        for url in urls where !isHandled(url) {
            pending.append(url)
        }
        startNextDownloads()
    }

    func cancelAll() {
        pending.removeAll()
        failed.removeAll()
        for download in current.values {
            download.task.cancel()
        }
        // Emptied at once, so the same URLs can be queued again right away. The slots are
        // not freed here: each cancelled task gives its slot back when it returns.
        current.removeAll()
    }

    // MARK: - ImageProviding

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func hasFailed(_ url: URL) -> Bool {
        failed.contains(url)
    }

    func request(_ url: URL, priority: ImagePriority) {
        guard image(for: url) == nil, current[url] == nil else { return }

        switch priority {
        case .normal:
            // A failed image is not retried on its own; that needs a high-priority request.
            guard !pending.contains(url), !failed.contains(url) else { return }
            pending.append(url)
        case .high:
            failed.remove(url)
            pending.removeAll { $0 == url }
            pending.insert(url, at: 0)
        }
        startNextDownloads()
    }

    func updates() -> AsyncStream<URL> {
        // One stream per subscriber: an AsyncStream delivers each element to a single consumer.
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: URL.self)
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.subscribers[id] = nil
            }
        }
        return stream
    }

    // MARK: - Scheduling

    private func isHandled(_ url: URL) -> Bool {
        image(for: url) != nil || current[url] != nil || pending.contains(url) || failed.contains(url)
    }

    /// The only place where downloads start.
    ///
    /// It is synchronous: there is no `await` between checking for a free slot and taking it,
    /// so nothing else can run on the main actor in between and take the same slot.
    /// That is what keeps the limit true no matter how calls interleave.
    private func startNextDownloads() {
        while occupiedSlots < maxConcurrentDownloads, !pending.isEmpty {
            let url = pending.removeFirst()
            occupiedSlots += 1
            lastDownloadID += 1
            let id = lastDownloadID

            let task = Task { [weak self, fetcher] in
                let result: Result<UIImage, any Error>
                do {
                    result = .success(try await fetcher.image(from: url))
                } catch {
                    result = .failure(error)
                }
                self?.finishDownload(id: id, of: url, with: result)
            }
            current[url] = Download(id: id, task: task)
            logger.debug("Download \(id) started, \(self.occupiedSlots) in flight")
        }
    }

    /// Runs exactly once for every started download, whether it succeeded, failed or was cancelled.
    private func finishDownload(id: Int, of url: URL, with result: Result<UIImage, any Error>) {
        occupiedSlots -= 1
        logger.debug("Download \(id) ended, \(self.occupiedSlots) in flight")
        defer { startNextDownloads() }

        // A download that was cancelled, or replaced by a newer one for the same URL,
        // only gives its slot back. Same idea as the generation check of the search.
        guard current[url]?.id == id else { return }
        current[url] = nil

        switch result {
        case .success(let image):
            cache.setObject(image, forKey: url as NSURL, cost: image.decodedByteCount)
        case .failure:
            failed.insert(url)
        }
        for subscriber in subscribers.values {
            subscriber.yield(url)
        }
    }
}

private extension UIImage {

    /// Memory the decoded pixels take: 4 bytes per pixel.
    var decodedByteCount: Int {
        Int(size.width * scale) * Int(size.height * scale) * 4
    }
}
