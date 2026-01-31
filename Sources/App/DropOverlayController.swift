import Cocoa
import Combine
import SwiftUI
import os

@MainActor
final class DropOverlayController {
    private let logger = Logger(subsystem: "com.net-snix.DropZone", category: "overlay")
    private let panel: NSPanel
    private let state = DropOverlayState()
    private let store: ZoneStore
    private var isVisible = false
    private var isDragging = false
    private var isPinned = false
    private var isArmed = false
    private var isShakeArmed = false
    private var isManualVisible = false
    private var lastKnownLocation: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()
    private var pendingHide: DispatchWorkItem?

    init(store: ZoneStore) {
        self.store = store
        let contentRect = NSRect(x: 0, y: 0, width: 280, height: 240)
        panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = DropBoxView(state: state, store: store)
        let hosting = NSHostingController(rootView: rootView)
        hosting.view.frame = NSRect(origin: .zero, size: contentRect.size)
        hosting.view.autoresizingMask = [.width, .height]
        panel.contentViewController = hosting
        panel.orderOut(nil)

        bindStore()
    }

    func updateInput(
        location: CGPoint,
        shiftDown: Bool,
        isDragging: Bool,
        isFileDrag: Bool,
        shiftPressed: Bool
    ) {
        lastKnownLocation = location
        self.isDragging = isDragging

        if isShakeArmed {
            if isDragging && isFileDrag {
                cancelPendingHide()
                if !isVisible {
                    show(at: location, reposition: true)
                }
                return
            } else {
                isShakeArmed = false
            }
        }

        if isArmed {
            if !(isDragging && isFileDrag && shiftDown) {
                isArmed = false
                scheduleHideIfNeeded()
            }
            return
        }

        scheduleHideIfNeeded()
    }

    func endDrag() {
        isDragging = false
        isArmed = false
        isShakeArmed = false
        scheduleHideIfNeeded()
    }

    func triggerShake(at location: CGPoint) {
        guard isDragging else { return }
        isShakeArmed = true
        cancelPendingHide()
        if !isVisible {
            show(at: location, reposition: true)
        }
    }

    func triggerShiftHold(at location: CGPoint) {
        guard isDragging else { return }
        isArmed = true
        cancelPendingHide()
        if !isVisible {
            show(at: location, reposition: true)
        }
    }

    func toggleManual(at location: CGPoint) {
        if isVisible && isManualVisible {
            isManualVisible = false
            scheduleHideIfNeeded()
            return
        }
        isManualVisible = true
        cancelPendingHide()
        show(at: location, reposition: true)
    }

    private func bindStore() {
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.handleItemsUpdate(items)
            }
            .store(in: &cancellables)
    }

    private func handleItemsUpdate(_ items: [ZoneItem]) {
        let shouldPin = !items.isEmpty
        if shouldPin {
            state.endHold()
        }
        if shouldPin != isPinned {
            isPinned = shouldPin
            if shouldPin && !isVisible {
                cancelPendingHide()
                let location = lastKnownLocation == .zero ? NSEvent.mouseLocation : lastKnownLocation
                show(at: location, reposition: true)
            }
            scheduleHideIfNeeded()
        } else {
            scheduleHideIfNeeded()
        }
    }

    private func show(at location: CGPoint, reposition: Bool) {
        if reposition {
            positionPanel(near: location)
        }
        guard !isVisible else { return }
        cancelPendingHide()
        isVisible = true
        state.isVisible = true
        logger.debug("Overlay show")
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
        state.isVisible = false
        state.isTargeted = false
        logger.debug("Overlay hide")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private func scheduleHideIfNeeded() {
        guard !isDragging && !isPinned && !isManualVisible else {
            cancelPendingHide()
            return
        }
        if state.isDropHold {
            cancelPendingHide()
            return
        }
        if !isVisible {
            return
        }
        cancelPendingHide()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.isDragging && !self.isPinned && !self.state.isDropHold {
                self.hide()
            }
        }
        pendingHide = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    private func positionPanel(near location: CGPoint) {
        let size = panel.frame.size
        let margin: CGFloat = 12

        if let anchor = ActiveWindowLocator.frontmostWindowAnchor() {
            let bounds = anchor.screen.visibleFrame
            if let frame = frameOutsideWindow(anchor.frame, panelSize: size, bounds: bounds, margin: margin) {
                panel.setFrame(frame, display: true)
                return
            }
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main else {
            return
        }

        var origin = CGPoint(x: location.x - size.width * 0.5, y: location.y - size.height - 24)
        let bounds = screen.visibleFrame
        origin.x = min(max(origin.x, bounds.minX + margin), bounds.maxX - size.width - margin)
        origin.y = min(max(origin.y, bounds.minY + margin), bounds.maxY - size.height - margin)

        let frame = NSRect(origin: origin, size: size)
        panel.setFrame(frame, display: true)
    }

    private func frameOutsideWindow(_ windowFrame: CGRect, panelSize: CGSize, bounds: CGRect, margin: CGFloat) -> CGRect? {
        let rightX = windowFrame.maxX + margin
        if rightX + panelSize.width <= bounds.maxX - margin {
            let y = clampedY(windowFrame.midY - panelSize.height * 0.5, bounds: bounds, panelSize: panelSize, margin: margin)
            return CGRect(origin: CGPoint(x: rightX, y: y), size: panelSize)
        }

        let leftX = windowFrame.minX - panelSize.width - margin
        if leftX >= bounds.minX + margin {
            let y = clampedY(windowFrame.midY - panelSize.height * 0.5, bounds: bounds, panelSize: panelSize, margin: margin)
            return CGRect(origin: CGPoint(x: leftX, y: y), size: panelSize)
        }

        let aboveY = windowFrame.maxY + margin
        if aboveY + panelSize.height <= bounds.maxY - margin {
            let x = clampedX(windowFrame.midX - panelSize.width * 0.5, bounds: bounds, panelSize: panelSize, margin: margin)
            return CGRect(origin: CGPoint(x: x, y: aboveY), size: panelSize)
        }

        let belowY = windowFrame.minY - panelSize.height - margin
        if belowY >= bounds.minY + margin {
            let x = clampedX(windowFrame.midX - panelSize.width * 0.5, bounds: bounds, panelSize: panelSize, margin: margin)
            return CGRect(origin: CGPoint(x: x, y: belowY), size: panelSize)
        }

        return nil
    }

    private func clampedX(_ value: CGFloat, bounds: CGRect, panelSize: CGSize, margin: CGFloat) -> CGFloat {
        min(max(value, bounds.minX + margin), bounds.maxX - panelSize.width - margin)
    }

    private func clampedY(_ value: CGFloat, bounds: CGRect, panelSize: CGSize, margin: CGFloat) -> CGFloat {
        min(max(value, bounds.minY + margin), bounds.maxY - panelSize.height - margin)
    }
}
