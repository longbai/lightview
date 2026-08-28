import AVFoundation
import CoreGraphics
import Foundation

public enum TransitionKind: Sendable, Equatable {
    case none
    case fade(duration: CMTime)
    case slide(duration: CMTime)

    public var duration: CMTime {
        switch self {
        case .none: .zero
        case .fade(let duration), .slide(let duration): duration
        }
    }
}

public enum AnimationDurationPolicy: Sendable, Equatable {
    case oneLoop
    case sourceLoopCount
    case maximum(CMTime)
}

public enum ExportCompositionMode: Sendable, Equatable {
    case fit
    case fill
}

public struct ExportColor: Sendable, Equatable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
        self.alpha = min(1, max(0, alpha))
    }

    public static let black = ExportColor(red: 0, green: 0, blue: 0)
    public static let white = ExportColor(red: 1, green: 1, blue: 1)
}

public enum ExportBackground: @unchecked Sendable {
    case solid(ExportColor)
    case image(CGImage, fallback: ExportColor)
}

public struct ExportSource: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case still
        case animation(frameDurations: [CMTime], sourceLoopCount: Int?)
    }

    public let identifier: String
    public let content: Content

    public static func still(identifier: String) -> ExportSource {
        ExportSource(identifier: identifier, content: .still)
    }

    public static func animation(
        identifier: String,
        frameDurations: [CMTime],
        sourceLoopCount: Int?
    ) -> ExportSource {
        ExportSource(
            identifier: identifier,
            content: .animation(frameDurations: frameDurations, sourceLoopCount: sourceLoopCount)
        )
    }
}

public struct MovieExportPlan: Sendable, Equatable {
    public let outputSize: CGSize
    public let frameRate: Int32
    public let sources: [ExportSource]
    public let staticDuration: CMTime
    public let transition: TransitionKind
    public let animationDurationPolicy: AnimationDurationPolicy

    public init(
        outputSize: CGSize,
        frameRate: Int32,
        sources: [ExportSource],
        staticDuration: CMTime,
        transition: TransitionKind,
        animationDurationPolicy: AnimationDurationPolicy
    ) {
        self.outputSize = outputSize
        self.frameRate = frameRate
        self.sources = sources
        self.staticDuration = staticDuration
        self.transition = transition
        self.animationDurationPolicy = animationDurationPolicy
    }
}

public struct FrameInstruction: Sendable, Equatable {
    public let presentationTime: CMTime
    public let primarySourceIndex: Int
    public let secondarySourceIndex: Int?
    public let transitionProgress: Double
    public let primaryLocalTime: CMTime
    public let secondaryLocalTime: CMTime?

    public init(
        presentationTime: CMTime,
        primarySourceIndex: Int,
        secondarySourceIndex: Int? = nil,
        transitionProgress: Double = 0,
        primaryLocalTime: CMTime,
        secondaryLocalTime: CMTime? = nil
    ) {
        self.presentationTime = presentationTime
        self.primarySourceIndex = primarySourceIndex
        self.secondarySourceIndex = secondarySourceIndex
        self.transitionProgress = min(1, max(0, transitionProgress))
        self.primaryLocalTime = primaryLocalTime
        self.secondaryLocalTime = secondaryLocalTime
    }
}

public struct ExportTimeline: Sendable, RandomAccessCollection {
    public typealias Index = Int
    public typealias Element = FrameInstruction

    private let instructions: [FrameInstruction]
    public let duration: CMTime

    public init(instructions: [FrameInstruction], duration: CMTime) {
        self.instructions = instructions
        self.duration = duration
    }

    public var startIndex: Int { instructions.startIndex }
    public var endIndex: Int { instructions.endIndex }
    public subscript(position: Int) -> FrameInstruction { instructions[position] }
}

public enum MovieExportError: Error, Sendable, Equatable {
    case invalidPlan(String)
    case cancelled
    case writerFailed(String)
}
