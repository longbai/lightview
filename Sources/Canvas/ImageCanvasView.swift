import AppKit
import LightViewCore

@MainActor
final class ImageCanvasView: NSView {
    var asset: RasterAsset? {
        didSet { needsDisplay = true }
    }
    var viewportState = ViewportState() {
        didSet { needsDisplay = true }
    }
    var viewerBackgroundColor: NSColor = .black {
        didSet { needsDisplay = true }
    }
    var backgroundAsset: RasterAsset? {
        didSet { needsDisplay = true }
    }

    private var dragOrigin: CGPoint?
    private var translationAtDragStart = CGPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("viewer.canvas")
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        viewerBackgroundColor.setFill()
        dirtyRect.fill()
        drawBackgroundImageIfNeeded()
        guard let asset,
              let scale = presentationScale(for: asset.originalPixelSize),
              let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.translateBy(
            x: bounds.midX + viewportState.translation.x,
            y: bounds.midY + viewportState.translation.y
        )
        context.rotate(by: CGFloat(viewportState.rotationDegrees) * .pi / 180)
        context.scaleBy(
            x: viewportState.isFlippedHorizontally ? -1 : 1,
            y: viewportState.isFlippedVertically ? -1 : 1
        )
        let width = asset.originalPixelSize.width * scale
        let height = asset.originalPixelSize.height * scale
        context.interpolationQuality = scale >= 1 ? .none : .high
        context.draw(asset.image, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        context.restoreGState()
    }

    private func drawBackgroundImageIfNeeded() {
        guard let backgroundAsset,
              let context = NSGraphicsContext.current?.cgContext,
              let scale = ViewportGeometry.fillScale(
                  imageSize: backgroundAsset.originalPixelSize,
                  viewportSize: bounds.size
              ) else { return }
        let size = CGSize(
            width: backgroundAsset.originalPixelSize.width * scale,
            height: backgroundAsset.originalPixelSize.height * scale
        )
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(
            backgroundAsset.image,
            in: CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        )
        context.restoreGState()
    }

    override func magnify(with event: NSEvent) {
        guard let asset else { return }
        let currentScale = presentationScale(for: asset.originalPixelSize) ?? viewportState.magnification
        let anchor = convert(event.locationInWindow, from: nil)
        let result = ViewportGeometry.anchoredZoom(
            from: currentScale,
            to: currentScale * (1 + event.magnification),
            translation: viewportState.translation,
            anchor: anchor,
            viewportSize: bounds.size
        )
        viewportState.mode = .manual
        viewportState.magnification = result.scale
        viewportState.translation = result.translation
    }

    override func scrollWheel(with event: NSEvent) {
        guard let asset else { return }
        viewportState.translation.x += event.scrollingDeltaX
        viewportState.translation.y -= event.scrollingDeltaY
        viewportState.translation = ViewportGeometry.clampedTranslation(
            imageSize: asset.originalPixelSize,
            viewportSize: bounds.size,
            scale: presentationScale(for: asset.originalPixelSize) ?? viewportState.magnification,
            rotationDegrees: viewportState.rotationDegrees,
            proposed: viewportState.translation
        ) ?? .zero
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragOrigin = convert(event.locationInWindow, from: nil)
        translationAtDragStart = viewportState.translation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let asset, let dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        let proposed = CGPoint(
            x: translationAtDragStart.x + point.x - dragOrigin.x,
            y: translationAtDragStart.y + point.y - dragOrigin.y
        )
        viewportState.translation = ViewportGeometry.clampedTranslation(
            imageSize: asset.originalPixelSize,
            viewportSize: bounds.size,
            scale: presentationScale(for: asset.originalPixelSize) ?? viewportState.magnification,
            rotationDegrees: viewportState.rotationDegrees,
            proposed: proposed
        ) ?? .zero
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
    }

    func setMode(_ mode: ViewportMode) {
        viewportState.mode = mode
        viewportState.translation = .zero
    }

    func zoom(by factor: CGFloat) {
        guard let asset else { return }
        let current = presentationScale(for: asset.originalPixelSize) ?? viewportState.magnification
        viewportState.mode = .manual
        viewportState.magnification = ViewportGeometry.clampedMagnification(current * factor)
    }

    func rotate(by degrees: Int) {
        viewportState.rotationDegrees = ViewportGeometry.normalizedRotation(viewportState.rotationDegrees + degrees)
        viewportState.translation = .zero
    }

    private func presentationScale(for imageSize: CGSize) -> CGFloat? {
        switch viewportState.mode {
        case .fit:
            ViewportGeometry.fitScale(imageSize: imageSize, viewportSize: bounds.size)
        case .fill:
            ViewportGeometry.fillScale(imageSize: imageSize, viewportSize: bounds.size)
        case .actualSize:
            ViewportGeometry.actualSizeScale(backingScale: window?.backingScaleFactor ?? 1)
        case .manual:
            viewportState.magnification
        }
    }
}
