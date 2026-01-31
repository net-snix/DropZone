import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DropBoxItemRow: NSViewRepresentable {
    let item: ZoneItem
    @ObservedObject var store: ZoneStore

    func makeNSView(context: Context) -> DragItemHostingView {
        let view = DragItemHostingView(rootView: DropBoxItemRowContent(item: item, store: store), store: store)
        view.item = item
        return view
    }

    func updateNSView(_ nsView: DragItemHostingView, context: Context) {
        nsView.rootView = DropBoxItemRowContent(item: item, store: store)
        nsView.item = item
        nsView.store = store
        nsView.invalidateIntrinsicContentSize()
    }

    final class DragItemHostingView: NSView, NSDraggingSource {
        var item: ZoneItem?
        var store: ZoneStore?
        private var mouseDownLocation: NSPoint?
        private var isDragging = false
        private var originalMovableBackground = false
        private let hostingView: NSHostingView<DropBoxItemRowContent>
        private var activeDragDelegates: [AnyObject] = []

        var rootView: DropBoxItemRowContent {
            get { hostingView.rootView }
            set { hostingView.rootView = newValue }
        }

        init(rootView: DropBoxItemRowContent, store: ZoneStore) {
            hostingView = NSHostingView(rootView: rootView)
            self.store = store
            super.init(frame: .zero)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            hostingView.fittingSize
        }

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownLocation = event.locationInWindow
            isDragging = false
            if let window {
                originalMovableBackground = window.isMovableByWindowBackground
                window.isMovableByWindowBackground = false
            }
            super.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard !isDragging, let start = mouseDownLocation else { return }
            let delta = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
            guard delta > 3 else { return }
            isDragging = true
            beginDragging(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownLocation = nil
            isDragging = false
            if let window {
                window.isMovableByWindowBackground = originalMovableBackground
            }
            super.mouseUp(with: event)
        }

        private func beginDragging(with event: NSEvent) {
            guard let item else { return }
            let itemsToDrag: [ZoneItem]
            if event.modifierFlags.contains(.shift), let store = self.store, store.items.count > 1 {
                itemsToDrag = store.items
            } else {
                itemsToDrag = [item]
            }
            activeDragDelegates.removeAll()
            let dragImage = makeDragImage(for: itemsToDrag)
            let localPoint = convert(event.locationInWindow, from: nil)
            let dragFrame = NSRect(
                x: localPoint.x - dragImage.size.width / 2,
                y: localPoint.y - dragImage.size.height / 2,
                width: dragImage.size.width,
                height: dragImage.size.height
            )
            let clearImage = NSImage(size: NSSize(width: 1, height: 1))
            var draggingItems: [NSDraggingItem] = []

            for (index, item) in itemsToDrag.enumerated() {
                let fileExtension = URL(fileURLWithPath: item.originalPath).pathExtension
                let fileType = UTType(filenameExtension: fileExtension)?.identifier ?? UTType.data.identifier
                let delegate = ZoneItemFilePromiseDelegate(item: item)
                let provider = NSFilePromiseProvider(fileType: fileType, delegate: delegate)
                activeDragDelegates.append(delegate)

                let draggingItem = NSDraggingItem(pasteboardWriter: provider)
                if index == 0 {
                    draggingItem.imageComponentsProvider = {
                        let component = NSDraggingImageComponent(key: .icon)
                        component.contents = dragImage
                        component.frame = NSRect(origin: .zero, size: dragImage.size)
                        return [component]
                    }
                    draggingItem.setDraggingFrame(dragFrame, contents: nil)
                } else {
                    draggingItem.setDraggingFrame(dragFrame, contents: clearImage)
                }
                draggingItems.append(draggingItem)
            }

            let session = beginDraggingSession(with: draggingItems, event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = false
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .move
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if let window {
                window.isMovableByWindowBackground = originalMovableBackground
            }
            activeDragDelegates.removeAll()
        }

        private func makeDragImage(for items: [ZoneItem]) -> NSImage {
            let visible = Array(items.prefix(4))
            let iconSize = NSSize(width: 64, height: 64)
            let offsetStep: CGFloat = 10
            let canvasSize = NSSize(width: 120, height: 120)

            let image = NSImage(size: canvasSize)
            image.lockFocus()

            for (index, item) in visible.enumerated().reversed() {
                let icon = NSWorkspace.shared.icon(forFile: item.originalPath)
                icon.size = iconSize
                let offset = CGFloat(index) * offsetStep
                let drawRect = NSRect(
                    x: (canvasSize.width - iconSize.width) / 2 + offset,
                    y: (canvasSize.height - iconSize.height) / 2 - offset,
                    width: iconSize.width,
                    height: iconSize.height
                )
                icon.draw(in: drawRect)
            }

            if items.count > visible.count {
                drawCountBadge(count: items.count, canvasSize: canvasSize)
            }

            image.unlockFocus()
            return image
        }

        private func drawCountBadge(count: Int, canvasSize: NSSize) {
            let badgeText = "\(count)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let textSize = badgeText.size(withAttributes: attributes)
            let padding: CGFloat = 6
            let badgeSize = NSSize(width: textSize.width + padding * 2, height: textSize.height + padding)
            let badgeRect = NSRect(
                x: canvasSize.width - badgeSize.width - 6,
                y: canvasSize.height - badgeSize.height - 6,
                width: badgeSize.width,
                height: badgeSize.height
            )

            let path = NSBezierPath(roundedRect: badgeRect, xRadius: badgeRect.height / 2, yRadius: badgeRect.height / 2)
            NSColor(calibratedRed: 0.1, green: 0.45, blue: 0.95, alpha: 0.9).setFill()
            path.fill()

            let textPoint = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            badgeText.draw(at: textPoint, withAttributes: attributes)
        }
    }
}

struct DropBoxItemRowContent: View {
    let item: ZoneItem
    @ObservedObject var store: ZoneStore

    var body: some View {
        VStack(spacing: 8) {
            fileIcon
                .frame(width: 56, height: 56)

            Text(item.fileName)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.panelFill.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.panelStroke, lineWidth: 1)
        )
    }

    private var fileIcon: some View {
        let image = resolvedIcon()
        return Image(nsImage: image)
            .resizable()
            .scaledToFit()
    }

    private func resolvedIcon() -> NSImage {
        if let url = store.resolvedURL(for: item) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 56, height: 56)
            return icon
        }
        return NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil) ?? NSImage()
    }
}
