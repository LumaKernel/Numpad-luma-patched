import AppKit
import ApplicationServices

struct FocusedInput {
    let field: CGRect?
    let caret: CGRect?

    static func capture(applicationPID: pid_t? = nil) -> FocusedInput? {
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return nil }
        let root = applicationPID.map(AXUIElementCreateApplication) ?? AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        var range: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
        guard hasRange || [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role as? String ?? "") else { return nil }
        func screenRect(_ rect: CGRect) -> CGRect? {
            guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite), rect.height > 0, rect.width >= 0 else { return nil }
            return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: max(1, rect.width), height: rect.height)
        }
        var caret: CGRect?
        if let range {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &value) == .success,
               let value, CFGetTypeID(value) == AXValueGetTypeID() {
                let ax = value as! AXValue
                var rect = CGRect.zero
                if AXValueGetType(ax) == .cgRect, AXValueGetValue(ax, .cgRect, &rect) { caret = screenRect(rect) }
            }
        }
        var position: CFTypeRef?, size: CFTypeRef?
        var field: CGRect?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
           let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            let p = position as! AXValue, s = size as! AXValue
            var point = CGPoint.zero, dimensions = CGSize.zero
            if AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize,
               AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &dimensions) {
                field = screenRect(CGRect(origin: point, size: dimensions))
            }
        }
        return field != nil || caret != nil ? FocusedInput(field: field, caret: caret) : nil
    }
}
