import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct OverlayDragSurface: NSViewRepresentable {
    let began: () -> Void
    let moved: (CGPoint, CGPoint) -> Void
    let ended: () -> Void
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {
        view.began = began; view.moved = moved; view.ended = ended
    }
    final class DragView: NSView {
        var began: (() -> Void)?
        var moved: ((CGPoint, CGPoint) -> Void)?
        var ended: (() -> Void)?
        private var mouseStart = CGPoint.zero
        private var windowStart = CGPoint.zero
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { false }
        override func mouseDown(with event: NSEvent) {
            mouseStart = NSEvent.mouseLocation
            windowStart = window?.frame.origin ?? .zero
            began?()
        }
        override func mouseDragged(with event: NSEvent) {
            let mouse = NSEvent.mouseLocation
            moved?(CGPoint(x: windowStart.x + mouse.x - mouseStart.x, y: windowStart.y + mouse.y - mouseStart.y), mouse)
        }
        override func mouseUp(with event: NSEvent) { ended?() }
    }
}
