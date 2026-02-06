import Foundation
import XCTest
@testable import DropZone

final class ZoneStoreSizeEstimationTests: XCTestCase {
    func testEstimatedFileSizeReturnsFileByteCount() throws {
        let fileURL = try makeTemporaryFile(named: "single.bin", size: 128)

        let size = ZoneStore.estimatedFileSize(at: fileURL)

        XCTAssertEqual(size, 128)
    }

    func testEstimatedFileSizeCapsDirectoryEntries() throws {
        let directoryURL = try makeTemporaryDirectory()
        for index in 0..<5 {
            _ = try makeFile(in: directoryURL, named: "entry-\(index).bin", size: 32)
        }

        let size = ZoneStore.estimatedFileSize(
            at: directoryURL,
            maxDirectoryEntries: 2,
            maxDirectoryBytes: .max
        )

        XCTAssertLessThanOrEqual(size, 64)
    }

    func testEstimatedFileSizeCapsDirectoryBytes() throws {
        let directoryURL = try makeTemporaryDirectory()
        for index in 0..<3 {
            _ = try makeFile(in: directoryURL, named: "chunk-\(index).bin", size: 10)
        }

        let size = ZoneStore.estimatedFileSize(
            at: directoryURL,
            maxDirectoryEntries: 100,
            maxDirectoryBytes: 15
        )

        XCTAssertEqual(size, 15)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func makeTemporaryFile(named: String, size: Int) throws -> URL {
        let root = try makeTemporaryDirectory()
        return try makeFile(in: root, named: named, size: size)
    }

    @discardableResult
    private func makeFile(in directory: URL, named: String, size: Int) throws -> URL {
        let fileURL = directory.appendingPathComponent(named)
        let data = Data(repeating: 0x41, count: size)
        try data.write(to: fileURL)
        return fileURL
    }
}
