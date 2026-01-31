import SwiftUI
import UniformTypeIdentifiers

struct InstantActionBar: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(InstantAction.allCases) { action in
                InstantActionPill(action: action)
            }
        }
    }
}

private struct InstantActionPill: View {
    let action: InstantAction
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: action.systemImage)
                .font(.system(size: 11, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                Text(action.subtitle)
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            Capsule()
                .fill(isTargeted ? Palette.accent.opacity(0.25) : Palette.panelFill.opacity(0.9))
        )
        .overlay(
            Capsule()
                .stroke(isTargeted ? Palette.accent : Palette.panelStroke, lineWidth: 1)
        )
        .onDrop(of: [UTType.fileURL, UTType.url], delegate: InstantActionDropDelegate(action: action, isTargeted: $isTargeted))
    }
}

private struct InstantActionDropDelegate: DropDelegate {
    let action: InstantAction
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL, UTType.url])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL, UTType.url])
        Task {
            let urls = await DragPasteboardReader.loadFileURLs(from: providers)
            let resolved = urls.isEmpty ? DragPasteboardReader.readURLsFromPasteboard() : urls
            await MainActor.run {
                _ = InstantActionRunner.run(action: action, urls: resolved)
                isTargeted = false
            }
        }
        return true
    }
}
