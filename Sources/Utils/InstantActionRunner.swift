import AppKit

@MainActor
enum InstantActionRunner {
    static func run(action: InstantAction, urls: [URL]) -> Bool {
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return false }

        do {
            switch action {
            case .newFolder:
                guard let destination = promptForNewFolder() else { return false }
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try FileMover.move(urls: fileURLs, to: destination)
            case .moveTo:
                guard let destination = promptForMoveDestination() else { return false }
                try FileMover.move(urls: fileURLs, to: destination)
            case .reveal:
                NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
                return true
            }
        } catch {
            NSSound.beep()
            return false
        }
        return true
    }

    private static func promptForMoveDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Move Files"
        panel.prompt = "Move"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func promptForNewFolder() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create Folder"
        panel.prompt = "Create"
        panel.nameFieldStringValue = "New Folder"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
