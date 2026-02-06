import AppKit
import UniformTypeIdentifiers

enum DragPasteboardReader {
    static func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask {
                    await loadFileURL(from: provider)
                }
            }

            var urls: [URL] = []
            for await url in group {
                if let url {
                    urls.append(url)
                }
            }
            return validatedFileURLs(urls)
        }
    }

    static func readURLsFromPasteboard() -> [URL] {
        let pasteboard = NSPasteboard(name: .drag)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        return validatedFileURLs(urls)
    }

    static func validatedFileURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var validURLs: [URL] = []
        for url in urls {
            guard let validURL = validatedFileURL(url) else { continue }
            let key = validURL.path
            if seenPaths.insert(key).inserted {
                validURLs.append(validURL)
            }
        }
        return validURLs
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadURL(from: provider, type: UTType.fileURL.identifier) {
                return validatedFileURL(url)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(from: provider, type: UTType.url.identifier) {
                return validatedFileURL(url)
            }
        }
        return nil
    }

    private static func loadURL(from provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                    return
                }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    private static func validatedFileURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return nil
        }
        return standardized
    }
}
