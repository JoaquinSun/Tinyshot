import AppKit
import SwiftUI

struct DraggableShot: NSViewRepresentable {
    let shot: Shot
    let image: NSImage?
    let prepareDrag: () throws -> DragTransfer
    let completeDrag: (DragTransfer, Bool) -> Void
    let onError: () -> Void
    func makeNSView(context: Context) -> ShotDragView { ShotDragView() }
    func updateNSView(_ view: ShotDragView, context: Context) {
        view.image = image
        view.prepareDrag = prepareDrag
        view.completeDrag = completeDrag
        view.onError = onError
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("拖动\(shot.name)到其他软件")
        view.needsDisplay = true
    }
}

final class ShotDragView: NSView, NSDraggingSource {
    var image: NSImage?
    var prepareDrag: (() throws -> DragTransfer)?
    var completeDrag: ((DragTransfer, Bool) -> Void)?
    var onError: (() -> Void)?
    private var activeDrag: (transfer: DragTransfer, completion: (DragTransfer, Bool) -> Void)?
    private var start: NSPoint?
    private var mouseDownEvent: NSEvent?
    override var isFlipped: Bool { true }
    // The panel can move by its background. The image must consume its own
    // gesture, otherwise a transparent NSView can pass it on as a window move.
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        mouseDownEvent = event
    }
    override func mouseDragged(with event: NSEvent) {
        guard activeDrag == nil, let start, let mouseDownEvent, let image, let prepareDrag, let completeDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        self.start = nil
        self.mouseDownEvent = nil
        let transfer: DragTransfer
        do { transfer = try prepareDrag() }
        catch { onError?(); return }
        activeDrag = (transfer, completeDrag)
        let item = NSDraggingItem(pasteboardWriter: transfer.pasteboardItem())
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: mouseDownEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // An empty operation means the destination rejected the drop or the user cancelled.
        guard let active = activeDrag else { return }
        activeDrag = nil
        let accepted = operation.contains(.copy)
        DispatchQueue.main.async { active.completion(active.transfer, accepted) }
    }
    override func mouseUp(with event: NSEvent) { start = nil; mouseDownEvent = nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
