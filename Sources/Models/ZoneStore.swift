import AppKit
import SwiftUI
import os

@MainActor
final class ZoneStore: ObservableObject {
    static let shared = ZoneStore()

    @Published private(set) var items: [ZoneItem] = []

    private let logger = Logger(subsystem: "com.net-snix.DropZone", category: "store")
    private let persistenceEnabled = false

    private var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (base ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("DropZone", isDirectory: true)
    }

    private var metadataURL: URL {
        storageDirectory.appendingPathComponent("metadata.json")
    }

    func load() {
        guard persistenceEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let data = try Data(contentsOf: metadataURL)
            let decoded = try JSONDecoder().decode([ZoneItem].self, from: data)
            items = decoded
        } catch {
            logger.debug("Load skipped: \(error.localizedDescription)")
        }
    }

    func reset() {
        items = []
        do {
            try FileManager.default.removeItem(at: metadataURL)
        } catch {
            logger.debug("Reset skipped: \(error.localizedDescription)")
        }
    }

    func save() {
        guard persistenceEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: metadataURL, options: [.atomic])
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
        }
    }

    func addItems(urls: [URL]) async -> Int {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return 0 }

        let existingPaths = Set(items.map { $0.originalPath })
        let logger = logger
        let newItems = await Task.detached(priority: .userInitiated) {
            ZoneStore.buildItems(urls: fileURLs, existingPaths: existingPaths, logger: logger)
        }.value

        guard !newItems.isEmpty else { return 0 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            items.insert(contentsOf: newItems, at: 0)
        }
        save()
        return newItems.count
    }

    func remove(item: ZoneItem) {
        withAnimation(.easeOut(duration: 0.2)) {
            items.removeAll { $0.id == item.id }
        }
        save()
    }

    func reveal(item: ZoneItem) {
        guard let url = resolvedURL(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func resolvedURL(for item: ZoneItem) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: item.bookmarkData,
                options: [.withSecurityScope],
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                refreshBookmark(for: item, url: url)
            }
            return url
        } catch {
            do {
                let url = try URL(
                    resolvingBookmarkData: item.bookmarkData,
                    options: [.withoutUI],
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    refreshBookmark(for: item, url: url)
                }
                return url
            } catch {
                logger.error("Resolve failed: \(error.localizedDescription)")
                return nil
            }
        }
    }

    func refreshBookmark(for item: ZoneItem, url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return
        }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let updated = ZoneItem(
            id: item.id,
            bookmarkData: data,
            originalPath: url.path,
            addedAt: item.addedAt,
            expiresAt: item.expiresAt,
            size: item.size
        )
        items[index] = updated
        save()
    }

    private nonisolated static func buildItems(
        urls: [URL],
        existingPaths: Set<String>,
        logger: Logger
    ) -> [ZoneItem] {
        var items: [ZoneItem] = []
        let now = Date()
        let expiry = Date.distantFuture

        for url in urls {
            guard !existingPaths.contains(url.path) else { continue }
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { url.stopAccessingSecurityScopedResource() }
            }
            let bookmarkData =
                (try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )) ??
                (try? url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ))
            guard let bookmarkData else {
                logger.error("Bookmark failed: \(url.path)")
                continue
            }

            let size = fileSize(at: url)
            let item = ZoneItem(
                id: UUID(),
                bookmarkData: bookmarkData,
                originalPath: url.path,
                addedAt: now,
                expiresAt: expiry,
                size: size
            )
            items.append(item)
        }
        return items
    }

    private nonisolated static func fileSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            return directorySize(at: url, fileManager: fileManager)
        }
        return Int64(values.fileSize ?? 0)
    }

    private nonisolated static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
