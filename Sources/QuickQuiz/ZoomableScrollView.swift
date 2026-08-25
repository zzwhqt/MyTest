import AppKit

final class ZoomableScrollView: NSScrollView {
    override func magnify(with event: NSEvent) {
        let center = documentView?.convert(event.locationInWindow, from: nil)
            ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        applyMagnification(delta: event.magnification, centeredAt: center)
    }

    override func smartMagnify(with event: NSEvent) {
        let center = documentView?.convert(event.locationInWindow, from: nil)
            ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        let target = magnification > minMagnification + 0.1 ? minMagnification : min(2, maxMagnification)
        setMagnification(target, centeredAt: center)
    }

    func applyMagnification(delta: CGFloat, centeredAt center: NSPoint) {
        let target = min(maxMagnification, max(minMagnification, magnification * (1 + delta)))
        setMagnification(target, centeredAt: center)
    }
}
