import AppKit
import LightViewCore

@MainActor
final class ImageInfoWindowController: NSWindowController {
    init(model: ImageInformationModel) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 360),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Image Information"
        window.center()
        window.setAccessibilityIdentifier("information.window")
        update(model: model)
    }

    required init?(coder: NSCoder) { nil }

    func update(model: ImageInformationModel) {
        let rows = model.rows.map { row -> [NSView] in
            let label = NSTextField(labelWithString: row.field.rawValue)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            let value = NSTextField(wrappingLabelWithString: row.value)
            value.isSelectable = true
            value.setAccessibilityLabel(row.value)
            return [label, value]
        }
        let grid = NSGridView(views: rows)
        let fieldColumn = grid.column(at: 0)
        fieldColumn.xPlacement = .trailing
        fieldColumn.width = 96
        let valueColumn = grid.column(at: 1)
        valueColumn.xPlacement = .fill
        valueColumn.width = 430
        grid.rowSpacing = 8
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
        window?.contentView = content
    }
}
