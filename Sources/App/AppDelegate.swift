import Cocoa
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct DragInputUpdate {
        let location: CGPoint
        let shiftDown: Bool
        let isDragging: Bool
        let isFileDrag: Bool
        let shiftPressed: Bool
    }

    private let logger = Logger(subsystem: "com.net-snix.DropZone", category: "app")
    private let dragMonitor = DragMonitor()
    private lazy var overlayController = DropOverlayController(store: ZoneStore.shared)
    private lazy var inputUpdateCoalescer = LatestValueCoalescer<DragInputUpdate> { [weak self] update in
        guard let self else { return }
        self.overlayController.updateInput(
            location: update.location,
            shiftDown: update.shiftDown,
            isDragging: update.isDragging,
            isFileDrag: update.isFileDrag,
            shiftPressed: update.shiftPressed
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("App launch")
        ZoneStore.shared.reset()
        bindDragMonitor()
        dragMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragMonitor.stop()
        logger.info("App terminate")
    }

    private func bindDragMonitor() {
        dragMonitor.onInputUpdate = { [weak self] location, shiftDown, isDragging, isFileDrag, shiftPressed in
            guard let self else { return }
            self.inputUpdateCoalescer.submit(
                DragInputUpdate(
                    location: location,
                    shiftDown: shiftDown,
                    isDragging: isDragging,
                    isFileDrag: isFileDrag,
                    shiftPressed: shiftPressed
                )
            )
        }
        dragMonitor.onShake = { [weak self] location in
            Task { @MainActor in
                self?.overlayController.triggerShake(at: location)
            }
        }
        dragMonitor.onShiftHold = { [weak self] location in
            Task { @MainActor in
                self?.overlayController.triggerShiftHold(at: location)
            }
        }
        dragMonitor.onShiftDoubleTap = { [weak self] location in
            Task { @MainActor in
                self?.overlayController.toggleManual(at: location)
            }
        }
        dragMonitor.onDragEnd = { [weak self] in
            Task { @MainActor in
                self?.overlayController.endDrag()
            }
        }
    }
}
