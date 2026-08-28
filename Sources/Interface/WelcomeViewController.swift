import AppKit
import LightViewCore

@MainActor
final class WelcomeViewController: NSViewController {
    var onOpen: (() -> Void)?

    override func loadView() {
        let effectView = NSVisualEffectView()
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.setAccessibilityIdentifier("welcome.view")

        let title = NSTextField(labelWithString: "LightView")
        title.font = .systemFont(ofSize: 30, weight: .semibold)
        title.alignment = .center
        let subtitle = NSTextField(labelWithString: L10n.text("welcome.subtitle"))
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        let openButton = NSButton(title: L10n.text("welcome.open"), target: self, action: #selector(openPressed))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"
        openButton.setAccessibilityIdentifier("welcome.openButton")

        let hint = NSTextField(labelWithString: L10n.text("welcome.drop"))
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center

        let principal: [CommandIdentifier] = [
            .open, .previous, .next, .zoomIn, .zoomOut, .fit, .fill, .actualSize,
            .rotateLeft, .rotateRight, .flipHorizontal, .flipVertical, .toggleFullScreen,
        ]
        let rows = principal.map { identifier -> [NSView] in
            let command = CommandCatalog.definition(for: identifier)
            let action = NSTextField(labelWithString: command.title)
            action.textColor = .secondaryLabelColor
            let key = NSTextField(labelWithString: command.shortcutDescription)
            key.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            key.alignment = .right
            return [action, key]
        }
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        grid.rowSpacing = 7
        grid.columnSpacing = 30

        let gesture = NSTextField(labelWithString: L10n.text("welcome.gestures"))
        gesture.textColor = .secondaryLabelColor
        gesture.alignment = .center

        let stack = NSStackView(views: [title, subtitle, openButton, hint, grid, gesture])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 13
        stack.setCustomSpacing(24, after: hint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: effectView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effectView.trailingAnchor, constant: -28),
        ])
        view = effectView
    }

    @objc private func openPressed() {
        onOpen?()
    }
}
