import Foundation

public enum CommandIdentifier: String, CaseIterable, Hashable, Sendable {
    case open
    case newWindow
    case closeWindow
    case previous
    case next
    case first
    case last
    case zoomIn
    case zoomOut
    case fit
    case fill
    case actualSize
    case rotateLeft
    case rotateRight
    case flipHorizontal
    case flipVertical
    case toggleFullScreen
    case togglePlayback
    case previousAnimationFrame
    case nextAnimationFrame
    case decreaseAnimationSpeed
    case increaseAnimationSpeed
    case toggleSlideshow
    case information
    case openWith
    case reload
    case revealInFinder
    case exportMP4
}

public struct CommandModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = CommandModifiers(rawValue: 1 << 0)
    public static let shift = CommandModifiers(rawValue: 1 << 1)
    public static let control = CommandModifiers(rawValue: 1 << 2)
    public static let option = CommandModifiers(rawValue: 1 << 3)
}

public struct CommandDefinition: Hashable, Sendable {
    public let identifier: CommandIdentifier
    public let title: String
    public let keyEquivalent: String
    public let modifiers: CommandModifiers
    public let shortcutDescription: String

    public init(
        identifier: CommandIdentifier,
        title: String,
        keyEquivalent: String,
        modifiers: CommandModifiers = [],
        shortcutDescription: String
    ) {
        self.identifier = identifier
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
        self.shortcutDescription = shortcutDescription
    }
}

public enum CommandCatalog {
    public static let all: [CommandDefinition] = [
        .init(identifier: .open, title: "Open Image or Folder…", keyEquivalent: "o", modifiers: .command, shortcutDescription: "⌘O"),
        .init(identifier: .newWindow, title: "New Window", keyEquivalent: "n", modifiers: .command, shortcutDescription: "⌘N"),
        .init(identifier: .closeWindow, title: "Close Window", keyEquivalent: "w", modifiers: .command, shortcutDescription: "⌘W"),
        .init(identifier: .previous, title: "Previous Image", keyEquivalent: "\u{F702}", shortcutDescription: "←"),
        .init(identifier: .next, title: "Next Image", keyEquivalent: "\u{F703}", shortcutDescription: "→"),
        .init(identifier: .first, title: "First Image", keyEquivalent: "\u{F702}", modifiers: .command, shortcutDescription: "⌘←"),
        .init(identifier: .last, title: "Last Image", keyEquivalent: "\u{F703}", modifiers: .command, shortcutDescription: "⌘→"),
        .init(identifier: .zoomIn, title: "Zoom In", keyEquivalent: "+", shortcutDescription: "+ / ↑"),
        .init(identifier: .zoomOut, title: "Zoom Out", keyEquivalent: "-", shortcutDescription: "− / ↓"),
        .init(identifier: .fit, title: "Fit to Window", keyEquivalent: "f", shortcutDescription: "F"),
        .init(identifier: .fill, title: "Fill Window", keyEquivalent: "f", modifiers: .shift, shortcutDescription: "⇧F"),
        .init(identifier: .actualSize, title: "Actual Size", keyEquivalent: "1", shortcutDescription: "1"),
        .init(identifier: .rotateLeft, title: "Rotate Left", keyEquivalent: "\u{F702}", modifiers: .shift, shortcutDescription: "⇧←"),
        .init(identifier: .rotateRight, title: "Rotate Right", keyEquivalent: "\u{F703}", modifiers: .shift, shortcutDescription: "⇧→"),
        .init(identifier: .flipHorizontal, title: "Flip Horizontal", keyEquivalent: "h", shortcutDescription: "H"),
        .init(identifier: .flipVertical, title: "Flip Vertical", keyEquivalent: "v", shortcutDescription: "V"),
        .init(identifier: .toggleFullScreen, title: "Enter Full Screen", keyEquivalent: "f", modifiers: [.control, .command], shortcutDescription: "⌃⌘F"),
        .init(identifier: .togglePlayback, title: "Play or Pause Animation", keyEquivalent: " ", shortcutDescription: "Space"),
        .init(identifier: .previousAnimationFrame, title: "Previous Animation Frame", keyEquivalent: "[", shortcutDescription: "["),
        .init(identifier: .nextAnimationFrame, title: "Next Animation Frame", keyEquivalent: "]", shortcutDescription: "]"),
        .init(identifier: .decreaseAnimationSpeed, title: "Decrease Animation Speed", keyEquivalent: "[", modifiers: .option, shortcutDescription: "⌥["),
        .init(identifier: .increaseAnimationSpeed, title: "Increase Animation Speed", keyEquivalent: "]", modifiers: .option, shortcutDescription: "⌥]"),
        .init(identifier: .toggleSlideshow, title: "Start or Stop Slideshow", keyEquivalent: "\r", shortcutDescription: "Return"),
        .init(identifier: .information, title: "File Information", keyEquivalent: "i", modifiers: .command, shortcutDescription: "⌘I"),
        .init(identifier: .openWith, title: "Open With…", keyEquivalent: "", shortcutDescription: ""),
        .init(identifier: .reload, title: "Reload", keyEquivalent: "r", modifiers: .command, shortcutDescription: "⌘R"),
        .init(identifier: .revealInFinder, title: "Reveal in Finder", keyEquivalent: "", shortcutDescription: ""),
        .init(identifier: .exportMP4, title: "Export MP4…", keyEquivalent: "e", modifiers: .command, shortcutDescription: "⌘E"),
    ]

    public static func definition(for identifier: CommandIdentifier) -> CommandDefinition {
        all.first(where: { $0.identifier == identifier })!
    }
}
