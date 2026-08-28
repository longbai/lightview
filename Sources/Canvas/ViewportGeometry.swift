import CoreGraphics
import Foundation

public enum ViewportMode: Sendable, Equatable {
    case fit
    case fill
    case actualSize
    case manual
}

public struct ViewportState: Sendable, Equatable {
    public var mode: ViewportMode
    public var magnification: CGFloat
    public var translation: CGPoint
    public var rotationDegrees: Int
    public var isFlippedHorizontally: Bool
    public var isFlippedVertically: Bool

    public init(
        mode: ViewportMode = .fit,
        magnification: CGFloat = 1,
        translation: CGPoint = .zero,
        rotationDegrees: Int = 0,
        isFlippedHorizontally: Bool = false,
        isFlippedVertically: Bool = false
    ) {
        self.mode = mode
        self.magnification = ViewportGeometry.clampedMagnification(magnification)
        self.translation = translation
        self.rotationDegrees = ViewportGeometry.normalizedRotation(rotationDegrees)
        self.isFlippedHorizontally = isFlippedHorizontally
        self.isFlippedVertically = isFlippedVertically
    }
}

public struct AnchoredZoomResult: Sendable, Equatable {
    public let scale: CGFloat
    public let translation: CGPoint
}

public enum ViewportGeometry {
    public static let magnificationRange: ClosedRange<CGFloat> = 0.01...128

    public static func fitScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat? {
        guard isValid(imageSize), isValid(viewportSize) else { return nil }
        return min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
    }

    public static func fillScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat? {
        guard isValid(imageSize), isValid(viewportSize) else { return nil }
        return max(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
    }

    public static func actualSizeScale(backingScale: CGFloat) -> CGFloat {
        guard backingScale.isFinite, backingScale > 0 else { return 1 }
        return clampedMagnification(1 / backingScale)
    }

    public static func displayedSize(
        imageSize: CGSize,
        scale: CGFloat,
        rotationDegrees: Int
    ) -> CGSize? {
        guard isValid(imageSize), scale.isFinite, scale > 0 else { return nil }
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        guard isValid(scaled) else { return nil }
        let rotation = normalizedRotation(rotationDegrees)
        if rotation == 90 || rotation == 270 {
            return CGSize(width: scaled.height, height: scaled.width)
        }
        return scaled
    }

    public static func windowContentSize(
        imageSize: CGSize,
        availableSize: CGSize,
        minimumSize: CGSize
    ) -> CGSize? {
        guard isValid(imageSize), isValid(availableSize), isValid(minimumSize) else { return nil }
        let scale = min(1, availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGSize(
            width: min(availableSize.width, max(minimumSize.width, fitted.width)),
            height: min(availableSize.height, max(minimumSize.height, fitted.height))
        )
    }

    public static func requiresHigherResolution(
        originalPixelSize: CGSize,
        decodedPixelSize: CGSize,
        presentationScale: CGFloat,
        backingScale: CGFloat
    ) -> Bool {
        guard isValid(originalPixelSize), isValid(decodedPixelSize),
              presentationScale.isFinite, presentationScale > 0,
              backingScale.isFinite, backingScale > 0 else { return false }
        let requiredWidth = originalPixelSize.width * presentationScale * backingScale
        let requiredHeight = originalPixelSize.height * presentationScale * backingScale
        return requiredWidth > decodedPixelSize.width * 1.05
            || requiredHeight > decodedPixelSize.height * 1.05
    }

    public static func anchoredZoom(
        from currentScale: CGFloat,
        to requestedScale: CGFloat,
        translation: CGPoint,
        anchor: CGPoint,
        viewportSize: CGSize
    ) -> AnchoredZoomResult {
        let oldScale = clampedMagnification(currentScale)
        let newScale = clampedMagnification(requestedScale)
        guard isValid(viewportSize), isFinite(anchor), isFinite(translation) else {
            return AnchoredZoomResult(scale: newScale, translation: .zero)
        }

        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let ratio = newScale / oldScale
        let offsetFromImageCenter = CGPoint(
            x: anchor.x - center.x - translation.x,
            y: anchor.y - center.y - translation.y
        )
        let newTranslation = CGPoint(
            x: anchor.x - center.x - offsetFromImageCenter.x * ratio,
            y: anchor.y - center.y - offsetFromImageCenter.y * ratio
        )
        return AnchoredZoomResult(scale: newScale, translation: newTranslation)
    }

    public static func clampedTranslation(
        imageSize: CGSize,
        viewportSize: CGSize,
        scale: CGFloat,
        rotationDegrees: Int,
        proposed: CGPoint
    ) -> CGPoint? {
        guard let displaySize = displayedSize(
            imageSize: imageSize,
            scale: scale,
            rotationDegrees: rotationDegrees
        ), isValid(viewportSize) else { return nil }

        let proposedX = proposed.x.isFinite ? proposed.x : 0
        let proposedY = proposed.y.isFinite ? proposed.y : 0
        let horizontalLimit = max(0, (displaySize.width - viewportSize.width) / 2)
        let verticalLimit = max(0, (displaySize.height - viewportSize.height) / 2)
        return CGPoint(
            x: min(max(proposedX, -horizontalLimit), horizontalLimit),
            y: min(max(proposedY, -verticalLimit), verticalLimit)
        )
    }

    public static func clampedMagnification(_ magnification: CGFloat) -> CGFloat {
        guard magnification.isFinite else { return 1 }
        return min(max(magnification, magnificationRange.lowerBound), magnificationRange.upperBound)
    }

    public static func normalizedRotation(_ degrees: Int) -> Int {
        let wrapped = ((degrees % 360) + 360) % 360
        return ((Int((Double(wrapped) / 90).rounded()) * 90) % 360)
    }

    private static func isValid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}
