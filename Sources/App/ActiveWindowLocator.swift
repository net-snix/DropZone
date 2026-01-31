import AppKit
import ApplicationServices

struct ActiveWindowAnchor {
    let frame: CGRect
    let screen: NSScreen
}

enum ActiveWindowLocator {
    static func frontmostWindowAnchor() -> ActiveWindowAnchor? {
        if let anchor = anchorFromAccessibility() {
            return anchor
        }
        return anchorFromWindowList()
    }

    private static func anchorFromAccessibility() -> ActiveWindowAnchor? {
        guard AXIsProcessTrusted() else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        if focusedResult != .success {
            let mainResult = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowValue)
            if mainResult != .success {
                return nil
            }
        }

        guard let windowElement = windowValue else { return nil }
        var positionValue: AnyObject?
        var sizeValue: AnyObject?

        guard AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(windowElement as! AXUIElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        return anchorFromFrame(CGRect(origin: position, size: size))
    }

    private static func anchorFromWindowList() -> ActiveWindowAnchor? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowInfo {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid == app.processIdentifier else {
                continue
            }
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            return anchorFromFrame(bounds)
        }
        return nil
    }

    private static func anchorFromFrame(_ frame: CGRect) -> ActiveWindowAnchor? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main else {
            return nil
        }
        return ActiveWindowAnchor(frame: frame, screen: screen)
    }
}
