import AppKit
import LightViewCore

@MainActor
final class ImageInfoWindowController: NSWindowController {
    init(model: ImageInformationModel) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = L10n.text("info.title")
        window.center()
        window.setAccessibilityIdentifier("information.window")
        update(model: model)
    }

    required init?(coder: NSCoder) { nil }

    func update(model: ImageInformationModel) {
        let fileHeading = sectionHeading("File & Image")
        let fileGrid = makeGrid(model.rows.map { ($0.field.rawValue, $0.value) })
        var arrangedViews: [NSView] = [fileHeading, fileGrid]
        if !model.exifRows.isEmpty {
            arrangedViews.append(sectionHeading("EXIF"))
            arrangedViews.append(makeGrid(model.exifRows.map { ($0.label, $0.value) }))
        }
        let formatNote = NSTextField(
            wrappingLabelWithString: "AVIF uses the macOS ImageIO decoder and requires macOS 13 or later."
        )
        formatNote.textColor = .secondaryLabelColor
        formatNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        formatNote.setAccessibilityIdentifier("information.avifRequirement")
        arrangedViews.append(formatNote)

        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: fileGrid)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let contentHeight = max(480, CGFloat(model.rows.count + model.exifRows.count) * 27 + 150)
        let document = FlippedDocumentView(frame: NSRect(x: 0, y: 0, width: 600, height: contentHeight))
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
        ])
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = document
        window?.contentView = scrollView
    }

    private func sectionHeading(_ text: String) -> NSTextField {
        let heading = NSTextField(labelWithString: text)
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        return heading
    }

    private func makeGrid(_ rows: [(String, String)]) -> NSGridView {
        let views = rows.map { labelText, valueText -> [NSView] in
            let label = NSTextField(labelWithString: labelText)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            let value = NSTextField(wrappingLabelWithString: valueText)
            value.isSelectable = true
            value.setAccessibilityLabel(valueText)
            return [label, value]
        }
        let grid = NSGridView(views: views)
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 110
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 1).width = 420
        grid.rowSpacing = 7
        grid.columnSpacing = 14
        return grid
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
