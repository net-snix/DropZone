import Foundation

enum FileMover {
    static func move(urls: [URL], to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for url in urls {
            let targetURL = uniqueURL(in: directory, originalName: url.lastPathComponent)
            do {
                try fileManager.moveItem(at: url, to: targetURL)
            } catch {
                try fileManager.copyItem(at: url, to: targetURL)
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static func uniqueURL(in directory: URL, originalName: String) -> URL {
        let fileManager = FileManager.default
        let baseURL = directory.appendingPathComponent(originalName)
        guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }

        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        var counter = 1
        var candidate = baseURL
        while fileManager.fileExists(atPath: candidate.path) {
            let name = "\(baseName)-\(counter)"
            let fileName = ext.isEmpty ? name : "\(name).\(ext)"
            candidate = directory.appendingPathComponent(fileName)
            counter += 1
        }
        return candidate
    }
}
