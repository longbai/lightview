import AppKit
import LightViewCore

@MainActor
final class ImageCanvasView: NSView {
    var onFullResolutionRequest: (() -> Void)?
    var asset: RasterAsset? {
        didSet {
            hasRequestedFullResolution = false
            animationImage = nil
            animationPixelSize = nil
            needsDisplay = true
            requestHigherResolutionIfNeeded()
        }
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
    private var animationImage: CGImage?
    private var animationPixelSize: CGSize?
    private var hasRequestedFullResolution = false

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
        guard let displayedImage,
              let displayedPixelSize,
              let scale = presentationScale(for: displayedPixelSize),
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
        let width = displayedPixelSize.width * scale
        let height = displayedPixelSize.height * scale
        context.interpolationQuality = scale >= 1 ? .none : .high
        context.draw(displayedImage, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
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
        guard let displayedPixelSize else { return }
        let currentScale = presentationScale(for: displayedPixelSize) ?? viewportState.magnification
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
        requestHigherResolutionIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let displayedPixelSize else { return }
        viewportState.translation.x += event.scrollingDeltaX
        viewportState.translation.y -= event.scrollingDeltaY
        viewportState.translation = ViewportGeometry.clampedTranslation(
            imageSize: displayedPixelSize,
            viewportSize: bounds.size,
            scale: presentationScale(for: displayedPixelSize) ?? viewportState.magnification,
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
        guard let displayedPixelSize, let dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        let proposed = CGPoint(
            x: translationAtDragStart.x + point.x - dragOrigin.x,
            y: translationAtDragStart.y + point.y - dragOrigin.y
        )
        viewportState.translation = ViewportGeometry.clampedTranslation(
            imageSize: displayedPixelSize,
            viewportSize: bounds.size,
            scale: presentationScale(for: displayedPixelSize) ?? viewportState.magnification,
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
        requestHigherResolutionIfNeeded()
    }

    func zoom(by factor: CGFloat) {
        guard let displayedPixelSize else { return }
        let current = presentationScale(for: displayedPixelSize) ?? viewportState.magnification
        viewportState.mode = .manual
        viewportState.magnification = ViewportGeometry.clampedMagnification(current * factor)
        requestHigherResolutionIfNeeded()
    }

    func rotate(by degrees: Int) {
        viewportState.rotationDegrees = ViewportGeometry.normalizedRotation(viewportState.rotationDegrees + degrees)
        viewportState.translation = .zero
    }

    func setAnimationFrame(_ frame: AnimationFrame, canvasPixelSize: CGSize) {
        asset = nil
        animationImage = frame.image
        animationPixelSize = canvasPixelSize
        needsDisplay = true
    }

    func clearImage() {
        asset = nil
        animationImage = nil
        animationPixelSize = nil
        needsDisplay = true
    }

    private var displayedImage: CGImage? { animationImage ?? asset?.image }
    private var displayedPixelSize: CGSize? { animationPixelSize ?? asset?.originalPixelSize }

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

    private func requestHigherResolutionIfNeeded() {
        guard !hasRequestedFullResolution, let asset,
              let scale = presentationScale(for: asset.originalPixelSize),
              ViewportGeometry.requiresHigherResolution(
                  originalPixelSize: asset.originalPixelSize,
                  decodedPixelSize: asset.decodedPixelSize,
                  presentationScale: scale,
                  backingScale: window?.backingScaleFactor ?? 1
              ) else { return }
        hasRequestedFullResolution = true
        onFullResolutionRequest?()
    }
}
