import AppKit
import LightViewCore

@MainActor
final class ViewerToolbarView: NSVisualEffectView {
    private var commandButtons: [NSButton] = []

    init(target: ViewerWindowController) {
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Image controls")
        setAccessibilityIdentifier("viewer.toolbar")

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 7, bottom: 5, right: 7)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (groupIndex, group) in ViewerToolbarCatalog.groups.enumerated() {
            if groupIndex > 0 { stack.addArrangedSubview(makeSeparator()) }
            for command in group {
                let button = makeButton(for: command, target: target)
                commandButtons.append(button)
                stack.addArrangedSubview(button)
            }
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func refreshAvailability(using validator: NSUserInterfaceValidations) {
        for button in commandButtons {
            let validationItem = NSMenuItem(title: "", action: button.action, keyEquivalent: "")
            button.isEnabled = validator.validateUserInterfaceItem(validationItem)
        }
    }

    private func makeButton(for command: CommandIdentifier, target: ViewerWindowController) -> NSButton {
        let definition = CommandCatalog.definition(for: command)
        let presentation = Self.presentation(for: command)
        let button: NSButton
        switch presentation {
        case .image(let name):
            let image = NSImage(named: name) ?? NSImage()
            image.isTemplate = true
            button = NSButton(image: image, target: target, action: Self.action(for: command))
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        case .text(let title, let size):
            button = NSButton(title: title, target: target, action: Self.action(for: command))
            button.font = NSFont.systemFont(ofSize: size, weight: .medium)
        }
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.focusRingType = .none
        button.toolTip = definition.shortcutDescription.isEmpty
            ? definition.title
            : "\(definition.title)  \(definition.shortcutDescription)"
        button.setAccessibilityLabel(definition.title)
        button.setAccessibilityIdentifier("viewer.toolbar.\(command.rawValue)")
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 20),
        ])
        return separator
    }

    private enum Presentation {
        case image(NSImage.Name)
        case text(String, CGFloat)
    }

    private static func presentation(for command: CommandIdentifier) -> Presentation {
        switch command {
        case .previous: .image(NSImage.goLeftTemplateName)
        case .next: .image(NSImage.goRightTemplateName)
        case .zoomOut: .text("−", 20)
        case .zoomIn: .text("+", 20)
        case .fit: .text("↙↗", 13)
        case .actualSize: .text("1:1", 11)
        case .rotateLeft: .image(NSImage.touchBarRotateLeftTemplateName)
        case .rotateRight: .image(NSImage.touchBarRotateRightTemplateName)
        case .flipHorizontal: .text("⇋", 18)
        case .information: .image(NSImage.touchBarGetInfoTemplateName)
        case .toggleFullScreen: .image(NSImage.touchBarEnterFullScreenTemplateName)
        default: preconditionFailure("Unsupported viewer toolbar command: \(command)")
        }
    }

    private static func action(for command: CommandIdentifier) -> Selector {
        switch command {
        case .previous: #selector(ViewerWindowController.previousImage(_:))
        case .next: #selector(ViewerWindowController.nextImage(_:))
        case .zoomOut: #selector(ViewerWindowController.zoomOut(_:))
        case .zoomIn: #selector(ViewerWindowController.zoomIn(_:))
        case .fit: #selector(ViewerWindowController.fitToWindow(_:))
        case .actualSize: #selector(ViewerWindowController.actualSize(_:))
        case .rotateLeft: #selector(ViewerWindowController.rotateLeft(_:))
        case .rotateRight: #selector(ViewerWindowController.rotateRight(_:))
        case .flipHorizontal: #selector(ViewerWindowController.flipHorizontal(_:))
        case .information: #selector(ViewerWindowController.showImageInformation(_:))
        case .toggleFullScreen: #selector(ViewerWindowController.toggleViewerFullScreen(_:))
        default: preconditionFailure("Unsupported viewer toolbar command: \(command)")
        }
    }
}
