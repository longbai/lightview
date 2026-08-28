import CoreGraphics

public struct DisplayRasterState: Equatable, Sendable {
    public var logicalViewportSize: CGSize
    public private(set) var backingScale: CGFloat
    public var imageSpaceCenter: CGPoint

    public init(
        logicalViewportSize: CGSize,
        backingScale: CGFloat,
        imageSpaceCenter: CGPoint
    ) {
        self.logicalViewportSize = logicalViewportSize
        self.backingScale = Self.validScale(backingScale)
        self.imageSpaceCenter = imageSpaceCenter
    }

    public var targetPixelSize: CGSize {
        guard logicalViewportSize.width.isFinite, logicalViewportSize.height.isFinite,
              logicalViewportSize.width > 0, logicalViewportSize.height > 0 else { return .zero }
        return CGSize(
            width: logicalViewportSize.width * backingScale,
            height: logicalViewportSize.height * backingScale
        )
    }

    public mutating func updateBackingScale(_ scale: CGFloat) {
        backingScale = Self.validScale(scale)
    }

    private static func validScale(_ scale: CGFloat) -> CGFloat {
        scale.isFinite && scale > 0 ? scale : 1
    }
}
