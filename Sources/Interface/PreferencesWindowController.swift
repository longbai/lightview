import AppKit
import LightViewCore

@MainActor
final class PreferencesWindowController: NSWindowController {
    var onPreferencesChanged: (() -> Void)?

    private let preferences: PreferencesStore
    private let appearancePopup = NSPopUpButton()
    private let backgroundPopup = NSPopUpButton()
    private let navigationWrapsButton = NSButton(checkboxWithTitle: "Wrap navigation at folder ends", target: nil, action: nil)
    private let welcomeButton = NSButton(checkboxWithTitle: "Show welcome guide in new windows", target: nil, action: nil)
    private let energySavingButton = NSButton(checkboxWithTitle: "Reduce animation work when inactive", target: nil, action: nil)
    private let preloadPopup = NSPopUpButton()
    private let initialZoomPopup = NSPopUpButton()
    private let zoomStepField = NSTextField()
    private let slideshowField = NSTextField()
    private let colorWell = NSColorWell()

    init(preferences: PreferencesStore) {
        self.preferences = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = L10n.text("preferences.title")
        window.center()
        window.setAccessibilityIdentifier("preferences.window")
        configureControls()
        window.contentView = makeContentView()
        loadValues()
    }

    required init?(coder: NSCoder) { nil }

    private func configureControls() {
        appearancePopup.addItems(withTitles: ["Follow System", "Light", "Dark"])
        backgroundPopup.addItems(withTitles: ["Black", "Dark Gray", "White", "Custom Color", "Custom Image…"])
        preloadPopup.addItems(withTitles: ["Off", "One neighbor", "Two neighbors"])
        initialZoomPopup.addItems(withTitles: ["Fit", "Fill", "Actual Size"])
        zoomStepField.placeholderString = "1.2"
        slideshowField.placeholderString = "5"
        if #available(macOS 14.0, *) {
            colorWell.supportsAlpha = true
        }

        appearancePopup.setAccessibilityIdentifier("preferences.appearance")
        backgroundPopup.setAccessibilityIdentifier("preferences.background")
        navigationWrapsButton.setAccessibilityIdentifier("preferences.navigationWraps")

        for control in [appearancePopup, backgroundPopup, preloadPopup, initialZoomPopup] {
            control.target = self
            control.action = #selector(controlChanged(_:))
        }
        for button in [navigationWrapsButton, welcomeButton, energySavingButton] {
            button.target = self
            button.action = #selector(controlChanged(_:))
        }
        for field in [zoomStepField, slideshowField] {
            field.target = self
            field.action = #selector(controlChanged(_:))
        }
        colorWell.target = self
        colorWell.action = #selector(controlChanged(_:))
    }

    private func makeContentView() -> NSView {
        let grid = NSGridView(views: [
            row("Appearance", appearancePopup),
            row("Canvas background", backgroundPopup),
            row("Custom color", colorWell),
            row("Preload", preloadPopup),
            row("Initial zoom", initialZoomPopup),
            row("Zoom step", zoomStepField),
            row("Slideshow seconds", slideshowField),
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 10
        grid.columnSpacing = 14

        let stack = NSStackView(views: [grid, navigationWrapsButton, welcomeButton, energySavingButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
        ])
        return content
    }

    private func row(_ title: String, _ control: NSView) -> [NSView] {
        [NSTextField(labelWithString: title), control]
    }

    private func loadValues() {
        appearancePopup.selectItem(at: preferences.appearance.index)
        backgroundPopup.selectItem(at: preferences.viewerBackground.index)
        navigationWrapsButton.state = preferences.navigationWraps ? .on : .off
        welcomeButton.state = preferences.showsWelcomeGuide ? .on : .off
        energySavingButton.state = preferences.animationEnergySaving ? .on : .off
        preloadPopup.selectItem(at: preferences.preloadLevel.rawValue)
        initialZoomPopup.selectItem(at: preferences.initialZoomMode.index)
        zoomStepField.doubleValue = preferences.zoomStep
        slideshowField.doubleValue = preferences.slideshowInterval
        if let color = NSColor(lightViewHex: preferences.customBackgroundColorHex) {
            colorWell.color = color
        }
    }

    @objc private func controlChanged(_ sender: Any?) {
        preferences.appearance = AppearancePreference.allCases[safe: appearancePopup.indexOfSelectedItem] ?? .followSystem
        let background = ViewerBackgroundPreference.allCases[safe: backgroundPopup.indexOfSelectedItem] ?? .black
        if background == .customImage {
            chooseBackgroundImage()
        } else {
            preferences.viewerBackground = background
        }
        preferences.navigationWraps = navigationWrapsButton.state == .on
        preferences.showsWelcomeGuide = welcomeButton.state == .on
        preferences.animationEnergySaving = energySavingButton.state == .on
        preferences.preloadLevel = PreloadLevel(rawValue: preloadPopup.indexOfSelectedItem) ?? .one
        preferences.initialZoomMode = InitialZoomMode.allCases[safe: initialZoomPopup.indexOfSelectedItem] ?? .fit
        preferences.zoomStep = zoomStepField.doubleValue
        preferences.slideshowInterval = slideshowField.doubleValue
        preferences.customBackgroundColorHex = colorWell.color.lightViewHex
        onPreferencesChanged?()
        loadValues()
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Background"
        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            backgroundPopup.selectItem(at: preferences.viewerBackground.index)
            return
        }
        do {
            let root = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("LightView/Backgrounds", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent("Background-\(UUID().uuidString).\(sourceURL.pathExtension)")
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            guard preferences.setBackgroundImageURL(destination) else { return }
            preferences.viewerBackground = .customImage
            onPreferencesChanged?()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

private extension AppearancePreference {
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

private extension ViewerBackgroundPreference {
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

private extension InitialZoomMode {
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension NSColor {
    convenience init?(lightViewHex value: String?) {
        guard let value, value.count == 9,
              let rgba = UInt32(value.dropFirst(), radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((rgba >> 24) & 0xFF) / 255,
            green: CGFloat((rgba >> 16) & 0xFF) / 255,
            blue: CGFloat((rgba >> 8) & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }

    var lightViewHex: String? {
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded()),
            Int((rgb.alphaComponent * 255).rounded())
        )
    }
}
