import Cocoa
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.net-snix.DropZone", category: "app")
    private let dragMonitor = DragMonitor()
    private lazy var overlayController = DropOverlayController(store: ZoneStore.shared)
    private let hotKeyManager = GlobalHotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("App launch")
        ZoneStore.shared.reset()
        bindDragMonitor()
        dragMonitor.start()
        registerHotKeys()
        hotKeyManager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragMonitor.stop()
        hotKeyManager.stop()
        logger.info("App terminate")
    }

    private func bindDragMonitor() {
        dragMonitor.onInputUpdate = { [weak self] location, shiftDown, isDragging, isFileDrag, shiftPressed in
            guard let self else { return }
            Task { @MainActor in
                self.overlayController.updateInput(
                    location: location,
                    shiftDown: shiftDown,
                    isDragging: isDragging,
                    isFileDrag: isFileDrag,
                    shiftPressed: shiftPressed
                )
            }
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
        dragMonitor.onDragEnd = { [weak self] in
            Task { @MainActor in
                self?.overlayController.endDrag()
            }
        }
    }

    private func registerHotKeys() {
        hotKeyManager.register(
            id: 1,
            keyCode: GlobalHotKeyManager.defaultToggleKeyCode,
            modifiers: GlobalHotKeyManager.defaultToggleModifiers
        ) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.overlayController.toggleManual(at: NSEvent.mouseLocation)
            }
        }
    }
}
