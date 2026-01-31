import Foundation

enum InstantAction: String, CaseIterable, Identifiable {
    case newFolder
    case moveTo
    case reveal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newFolder: return "New Folder"
        case .moveTo: return "Move To"
        case .reveal: return "Reveal"
        }
    }

    var subtitle: String {
        switch self {
        case .newFolder: return "Create + move"
        case .moveTo: return "Choose folder"
        case .reveal: return "Finder"
        }
    }

    var systemImage: String {
        switch self {
        case .newFolder: return "folder.badge.plus"
        case .moveTo: return "folder"
        case .reveal: return "magnifyingglass"
        }
    }
}
