import SwiftUI
import UniformTypeIdentifiers

struct DropBoxView: View {
    @ObservedObject var state: DropOverlayState
    @ObservedObject var store: ZoneStore

    private let panelCorner: CGFloat = 22

    var body: some View {
        ZStack {
            panelSurface
                .allowsHitTesting(false)
                .zIndex(0)
            content
                .zIndex(1)
        }
        .frame(width: 280, height: 240)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL, UTType.url], delegate: DropBoxDropDelegate(state: state, store: store) { urls in
            Task {
                let added = await store.addItems(urls: urls)
                await MainActor.run {
                    if added == 0 {
                        state.endHold()
                    }
                }
            }
            state.pulse()
        })
        .scaleEffect(state.isPulsing ? 1.02 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: state.isPulsing)
    }

    private var panelSurface: some View {
        RoundedRectangle(cornerRadius: panelCorner, style: .continuous)
            .fill(Palette.panelFill)
            .overlay(
                RoundedRectangle(cornerRadius: panelCorner, style: .continuous)
                    .stroke(Palette.panelStroke, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: panelCorner - 6, style: .continuous)
                    .stroke(state.isTargeted ? Palette.accent : Palette.accentCool, lineWidth: 1.2)
                    .opacity(state.isTargeted ? 0.9 : 0.3)
            )
            .shadow(color: Color.black.opacity(state.isTargeted ? 0.45 : 0.3), radius: 22, x: 0, y: 12)
    }

    private var content: some View {
        ZStack {
            if store.items.isEmpty {
                emptyState
            } else {
                itemStack
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragHandle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            iconBubble

            VStack(spacing: 4) {
                Text(state.isTargeted ? "Release to stash" : "Drop to stash")
                    .font(.custom("New York", size: 16))
                    .foregroundStyle(Palette.textPrimary)
            }

            if state.isTargeted {
                InstantActionBar()
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var itemStack: some View {
        let maxVisible = 5
        let visible = Array(store.items.prefix(maxVisible)).reversed()
        let total = visible.count

        return ZStack(alignment: .center) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                let depth = total - 1 - index
                DropBoxItemRow(item: item, store: store)
                    .frame(width: 190, height: 110)
                    .offset(x: CGFloat(depth) * 9, y: CGFloat(depth) * -7)
                    .scaleEffect(1 - CGFloat(depth) * 0.03)
                    .rotationEffect(.degrees(Double(depth) * 1.2))
                    .zIndex(Double(index))
            }
            countBadge
                .offset(x: 80, y: -70)
                .zIndex(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countBadge: some View {
        Text("\(store.items.count)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.textPrimary)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(
                Capsule().fill(Palette.panelFill.opacity(0.9))
            )
            .overlay(
                Capsule().stroke(Palette.panelStroke, lineWidth: 1)
            )
    }

    private var iconBubble: some View {
        ZStack {
            Circle()
                .fill(Palette.accent.opacity(0.16))

            Image(systemName: "doc.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Palette.accent)
        }
        .frame(width: 54, height: 54)
        .shadow(color: Palette.accent.opacity(0.4), radius: 18, x: 0, y: 8)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private struct DropBoxDropDelegate: DropDelegate {
    let state: DropOverlayState
    let store: ZoneStore
    let onDrop: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL, UTType.url])
    }

    func dropEntered(info: DropInfo) {
        state.isTargeted = true
    }

    func dropExited(info: DropInfo) {
        state.isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL, UTType.url])
        state.beginHold()
        Task {
            let urls = await DragPasteboardReader.loadFileURLs(from: providers)
            let resolved = urls.isEmpty ? DragPasteboardReader.readURLsFromPasteboard() : urls
            if !resolved.isEmpty {
                onDrop(resolved)
            } else {
                await MainActor.run {
                    state.endHold()
                }
            }
            await MainActor.run {
                state.isTargeted = false
            }
        }
        return true
    }
}
