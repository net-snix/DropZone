import Cocoa

final class DragMonitor {
    var onInputUpdate: ((CGPoint, Bool, Bool, Bool, Bool) -> Void)?
    var onDragEnd: (() -> Void)?
    var onShake: ((CGPoint) -> Void)?
    var onShiftHold: ((CGPoint) -> Void)?
    var onShiftDoubleTap: ((CGPoint) -> Void)?

    private var flagsMonitor: Any?
    private var dragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var dragPollTimer: Timer?
    private var shiftHoldTimer: Timer?

    private var shiftDown = false
    private var isDragging = false
    private var isFileDrag = false
    private let shakeDetector = ShakeDetector()
    private let shiftHoldDelay: TimeInterval = 0.25
    private let shiftDoubleTapInterval: TimeInterval = 0.35
    private var lastShiftTapTimestamp: TimeInterval?

    func start() {
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            self?.handleDrag(event)
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.endDrag()
        }
    }

    func stop() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
        flagsMonitor = nil
        dragMonitor = nil
        mouseUpMonitor = nil
        dragPollTimer?.invalidate()
        dragPollTimer = nil
        shiftHoldTimer?.invalidate()
        shiftHoldTimer = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        if NSEvent.pressedMouseButtons == 0 && isDragging {
            endDrag()
        }
        let newShiftDown = event.modifierFlags.contains(.shift)
        let shiftPressed = newShiftDown && !shiftDown
        shiftDown = newShiftDown
        if isDragging {
            isFileDrag = currentDragHasFileURLs()
        } else {
            isFileDrag = false
        }
        updateShiftHoldTimer(at: NSEvent.mouseLocation)
        handleShiftDoubleTap(event: event, shiftPressed: shiftPressed)
        onInputUpdate?(NSEvent.mouseLocation, shiftDown, isDragging, isFileDrag, shiftPressed)
    }

    private func handleDrag(_ event: NSEvent) {
        if NSEvent.pressedMouseButtons == 0 {
            endDrag()
            return
        }
        isDragging = true
        startDragPollingIfNeeded()
        shiftDown = event.modifierFlags.contains(.shift)
        isFileDrag = currentDragHasFileURLs()
        let location = NSEvent.mouseLocation
        if isFileDrag, shakeDetector.ingest(point: location) {
            onShake?(location)
        }
        updateShiftHoldTimer(at: location)
        onInputUpdate?(location, shiftDown, isDragging, isFileDrag, false)
    }

    private func endDrag() {
        isDragging = false
        isFileDrag = false
        shakeDetector.reset()
        shiftHoldTimer?.invalidate()
        shiftHoldTimer = nil
        dragPollTimer?.invalidate()
        dragPollTimer = nil
        onDragEnd?()
    }

    private func startDragPollingIfNeeded() {
        guard dragPollTimer == nil else { return }
        dragPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let leftDown = (NSEvent.pressedMouseButtons & 1) != 0
            if self.isDragging && !leftDown {
                self.endDrag()
            }
        }
        if let dragPollTimer {
            RunLoop.main.add(dragPollTimer, forMode: .common)
        }
    }

    private func updateShiftHoldTimer(at location: CGPoint) {
        if isDragging, isFileDrag, shiftDown {
            guard shiftHoldTimer == nil else { return }
            shiftHoldTimer = Timer.scheduledTimer(withTimeInterval: shiftHoldDelay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.shiftHoldTimer = nil
                if self.isDragging && self.isFileDrag && self.shiftDown {
                    self.onShiftHold?(location)
                }
            }
            if let shiftHoldTimer {
                RunLoop.main.add(shiftHoldTimer, forMode: .common)
            }
        } else {
            shiftHoldTimer?.invalidate()
            shiftHoldTimer = nil
        }
    }

    private func handleShiftDoubleTap(event: NSEvent, shiftPressed: Bool) {
        guard shiftPressed else { return }
        guard !isDragging else { return }
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.shift] else {
            lastShiftTapTimestamp = nil
            return
        }
        let now = event.timestamp
        if let last = lastShiftTapTimestamp, now - last <= shiftDoubleTapInterval {
            lastShiftTapTimestamp = nil
            onShiftDoubleTap?(NSEvent.mouseLocation)
        } else {
            lastShiftTapTimestamp = now
        }
    }

    private func currentDragHasFileURLs() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: options)
    }
}
