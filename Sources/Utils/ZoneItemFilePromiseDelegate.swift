import AppKit
import os

final class ZoneItemFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let item: ZoneItem
    private let logger = Logger(subsystem: "com.net-snix.DropZone", category: "drag")

    init(item: ZoneItem) {
        self.item = item
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        item.fileName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [item, logger] in
            let result = FilePromiseMover.move(item: item, to: url, logger: logger)
            completionHandler(result)
        }
    }
}

enum FilePromiseMover {
    static func move(item: ZoneItem, to destinationURL: URL, logger: Logger) -> Error? {
        do {
            var isStale = false
            let sourceURL = try URL(
                resolvingBookmarkData: item.bookmarkData,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { sourceURL.stopAccessingSecurityScopedResource() }
            }
            if isStale {
                Task { @MainActor in
                    ZoneStore.shared.refreshBookmark(for: item, url: sourceURL)
                }
            }
            let targetURL = uniqueURL(for: destinationURL)
            let fileManager = FileManager.default

            try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            do {
                try fileManager.moveItem(at: sourceURL, to: targetURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                try fileManager.removeItem(at: sourceURL)
            }

            Task { @MainActor in
                ZoneStore.shared.remove(item: item)
            }
            return nil
        } catch {
            logger.error("Move failed: \(error.localizedDescription)")
            return error
        }
    }

    private static func uniqueURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        var candidate = url
        while fileManager.fileExists(atPath: candidate.path) {
            let name = "\(baseName)-\(counter)"
            let fileName = ext.isEmpty ? name : "\(name).\(ext)"
            candidate = url.deletingLastPathComponent().appendingPathComponent(fileName)
            counter += 1
        }
        return candidate
    }
}
