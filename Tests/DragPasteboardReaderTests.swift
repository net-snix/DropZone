import Foundation
import XCTest
@testable import DropZone

final class DragPasteboardReaderTests: XCTestCase {
    func testValidatedFileURLsRejectsNonFileAndMissingPaths() throws {
        let fileURL = try makeTemporaryFile(named: "keep.txt", contents: "ok")
        let missingFileURL = fileURL.deletingLastPathComponent().appendingPathComponent("missing.txt")
        let webURL = try XCTUnwrap(URL(string: "https://example.com/file.txt"))

        let validated = DragPasteboardReader.validatedFileURLs([fileURL, missingFileURL, webURL])

        XCTAssertEqual(validated, [fileURL.standardizedFileURL])
    }

    func testValidatedFileURLsDeduplicatesByStandardizedPath() throws {
        let fileURL = try makeTemporaryFile(named: "duplicate.txt", contents: "ok")
        let duplicateURL = URL(fileURLWithPath: fileURL.path)

        let validated = DragPasteboardReader.validatedFileURLs([fileURL, duplicateURL])

        XCTAssertEqual(validated.count, 1)
        XCTAssertEqual(validated.first, fileURL.standardizedFileURL)
    }

    private func makeTemporaryFile(named: String, contents: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let fileURL = root.appendingPathComponent(named)
        let data = try XCTUnwrap(contents.data(using: .utf8))
        try data.write(to: fileURL)
        return fileURL
    }
}
