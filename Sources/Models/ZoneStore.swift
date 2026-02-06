import AppKit
import SwiftUI
import os

@MainActor
final class ZoneStore: ObservableObject {
    static let shared = ZoneStore()
    nonisolated static let directoryScanEntryLimit = 10_000
    nonisolated static let directoryScanByteLimit: Int64 = 5 * 1024 * 1024 * 1024

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

            let size = estimatedFileSize(at: url, logger: logger)
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

    nonisolated static func estimatedFileSize(
        at url: URL,
        maxDirectoryEntries: Int = directoryScanEntryLimit,
        maxDirectoryBytes: Int64 = directoryScanByteLimit,
        fileManager: FileManager = .default,
        logger: Logger? = nil
    ) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            return directorySize(
                at: url,
                fileManager: fileManager,
                maxEntries: maxDirectoryEntries,
                maxBytes: maxDirectoryBytes,
                logger: logger
            )
        }
        return Int64(values.fileSize ?? 0)
    }

    private nonisolated static func directorySize(
        at url: URL,
        fileManager: FileManager,
        maxEntries: Int,
        maxBytes: Int64,
        logger: Logger?
    ) -> Int64 {
        guard maxEntries > 0, maxBytes > 0 else { return 0 }
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        ) else {
            return 0
        }

        var total: Int64 = 0
        var scannedEntries = 0
        for case let fileURL as URL in enumerator {
            if scannedEntries >= maxEntries || total >= maxBytes {
                logger?.debug("Directory size scan capped at \(url.path, privacy: .public)")
                break
            }

            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize > 0 else {
                continue
            }

            scannedEntries += 1
            total += Int64(fileSize)
            if total > maxBytes {
                total = maxBytes
                logger?.debug("Directory size byte cap reached at \(url.path, privacy: .public)")
                break
            }
        }
        return total
    }
}
