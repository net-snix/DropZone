import Foundation

struct ZoneItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let bookmarkData: Data
    let originalPath: String
    let addedAt: Date
    let expiresAt: Date
    let size: Int64

    var fileName: String { URL(fileURLWithPath: originalPath).lastPathComponent }
}
