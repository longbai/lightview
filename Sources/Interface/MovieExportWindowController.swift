import AppKit
import AVFoundation
import LightViewCore
import UniformTypeIdentifiers

@MainActor
final class MovieExportWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    var onClose: (() -> Void)?

    private let currentURL: URL
    private let folderURLs: [URL]
    private let sourceScope = NSPopUpButton()
    private let preset = NSPopUpButton()
    private let composition = NSPopUpButton()
    private let transition = NSPopUpButton()
    private let staticDuration = NSTextField(string: "2.0")
    private let animationPolicy = NSPopUpButton()
    private let maximumDuration = NSTextField(string: "10.0")
    private let background = NSPopUpButton()
    private let chooseBackgroundButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: L10n.text("export.ready"))
    private let exportButton = NSButton()
    private let cancelButton = NSButton()
    private let revealButton = NSButton()
    private var backgroundImageURL: URL?
    private var cancellation: ExportCancellation?
    private var exportedURL: URL?
    private var didNotifyClose = false

    init(currentURL: URL, folderURLs: [URL]) {
        self.currentURL = currentURL.standardizedFileURL
        self.folderURLs = folderURLs.map(\.standardizedFileURL)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = L10n.text("export.title")
        window.delegate = self
        window.center()
        window.setAccessibilityIdentifier("export.window")
        configureControls()
        buildContent()
        updateControlState()
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) {
        cancellation?.cancel()
        notifyCloseOnce()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateControlState()
    }

    private func configureControls() {
        configure(sourceScope, titles: [L10n.text("export.currentImage"), L10n.text("export.currentFolder")], identifier: "export.sourceScope")
        sourceScope.item(at: 1)?.isEnabled = folderURLs.count > 1
        configure(preset, titles: ["480p", "720p", "1080p"], identifier: "export.preset")
        preset.selectItem(at: 1)
        configure(composition, titles: [L10n.text("export.fit"), L10n.text("export.fill")], identifier: "export.composition")
        configure(transition, titles: [L10n.text("export.fade"), L10n.text("export.slide")], identifier: "export.transition")
        configure(
            animationPolicy,
            titles: [L10n.text("export.oneLoop"), L10n.text("export.sourceLoops"), L10n.text("export.maximum")],
            identifier: "export.animationPolicy"
        )
        configure(background, titles: [L10n.text("export.black"), L10n.text("export.white"), L10n.text("export.image")], identifier: "export.background")
        background.target = self
        background.action = #selector(selectionChanged(_:))
        animationPolicy.target = self
        animationPolicy.action = #selector(selectionChanged(_:))

        for (field, identifier) in [
            (staticDuration, "export.staticDuration"),
            (maximumDuration, "export.maximumDuration"),
        ] {
            field.delegate = self
            field.alignment = .right
            field.setAccessibilityIdentifier(identifier)
        }

        chooseBackgroundButton.title = L10n.text("export.chooseImage")
        chooseBackgroundButton.bezelStyle = .rounded
        chooseBackgroundButton.target = self
        chooseBackgroundButton.action = #selector(chooseBackground(_:))
        chooseBackgroundButton.setAccessibilityIdentifier("export.chooseBackground")

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0
        progressIndicator.setAccessibilityIdentifier("export.progress")

        exportButton.title = L10n.text("export.start")
        exportButton.bezelStyle = .rounded
        exportButton.keyEquivalent = "\r"
        exportButton.target = self
        exportButton.action = #selector(beginExport(_:))
        exportButton.setAccessibilityIdentifier("export.start")

        cancelButton.title = L10n.text("export.cancel")
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelOrClose(_:))
        cancelButton.setAccessibilityIdentifier("export.cancel")

        revealButton.title = L10n.text("export.reveal")
        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(revealOutput(_:))
        revealButton.isHidden = true
        revealButton.setAccessibilityIdentifier("export.reveal")
    }

    private func buildContent() {
        let form = NSGridView(views: [
            row("Source", sourceScope),
            row("Resolution", preset),
            row("Composition", composition),
            row("Transition", transition),
            row("Still duration (seconds)", staticDuration),
            row("Animation duration", animationPolicy),
            row("Maximum duration (seconds)", maximumDuration),
            row("Background", background),
            row("Background image", chooseBackgroundButton),
        ])
        form.rowSpacing = 10
        form.columnSpacing = 16
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 0).width = 190
        form.column(at: 1).xPlacement = .fill
        form.column(at: 1).width = 260

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        let buttons = NSStackView(views: [revealButton, NSView(), cancelButton, exportButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        let stack = NSStackView(views: [form, progressIndicator, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window?.contentView = content
    }

    private func row(_ title: String, _ control: NSView) -> [NSView] {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        return [label, control]
    }

    private func configure(_ popup: NSPopUpButton, titles: [String], identifier: String) {
        popup.addItems(withTitles: titles)
        popup.setAccessibilityIdentifier(identifier)
    }

    @objc private func selectionChanged(_ sender: Any?) {
        updateControlState()
    }

    @objc private func chooseBackground(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Choose Background Image"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return }
        backgroundImageURL = panel.url
        background.selectItem(at: 2)
        updateControlState()
    }

    @objc private func beginExport(_ sender: Any?) {
        guard validateDurations() else { return }
        let savePanel = NSSavePanel()
        savePanel.title = L10n.text("export.title")
        savePanel.nameFieldStringValue = currentURL.deletingPathExtension().lastPathComponent + ".mp4"
        if #available(macOS 11.0, *) {
            savePanel.allowedContentTypes = [.mpeg4Movie]
        } else {
            savePanel.allowedFileTypes = ["mp4"]
        }
        guard savePanel.runModal() == .OK, let destination = savePanel.url else { return }

        let urls = sourceScope.indexOfSelectedItem == 1 ? folderURLs : [currentURL]
        let outputSize = selectedOutputSize
        let staticSeconds = staticDuration.doubleValue
        let maximumSeconds = maximumDuration.doubleValue
        let transitionKind: TransitionKind = transition.indexOfSelectedItem == 0
            ? .fade(duration: CMTime(seconds: 0.25, preferredTimescale: 600))
            : .slide(duration: CMTime(seconds: 0.25, preferredTimescale: 600))
        let compositionMode: ExportCompositionMode = composition.indexOfSelectedItem == 0 ? .fit : .fill
        let animationDurationPolicy: AnimationDurationPolicy
        switch animationPolicy.indexOfSelectedItem {
        case 0: animationDurationPolicy = .oneLoop
        case 1: animationDurationPolicy = .sourceLoopCount
        default: animationDurationPolicy = .maximum(
            CMTime(seconds: maximumSeconds, preferredTimescale: 600)
        )
        }
        let backgroundIndex = background.indexOfSelectedItem
        let backgroundURL = backgroundImageURL
        setExporting(true, status: L10n.text("export.preparing"))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let repository = ExportImageRepository(urls: urls, targetSize: outputSize)
                let sources = try repository.prepareSources()
                let exportBackground: ExportBackground
                if backgroundIndex == 2, let backgroundURL {
                    exportBackground = .image(
                        try repository.decodeBackgroundImage(at: backgroundURL),
                        fallback: .black
                    )
                } else {
                    exportBackground = .solid(backgroundIndex == 1 ? .white : .black)
                }
                let plan = MovieExportPlan(
                    outputSize: outputSize,
                    frameRate: 30,
                    sources: sources,
                    staticDuration: CMTime(seconds: staticSeconds, preferredTimescale: 600),
                    transition: transitionKind,
                    animationDurationPolicy: animationDurationPolicy
                )
                DispatchQueue.main.async { [weak self] in
                    self?.startPreparedExport(
                        repository: repository,
                        plan: plan,
                        composition: compositionMode,
                        background: exportBackground,
                        destination: destination
                    )
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.setExporting(false, status: "Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startPreparedExport(
        repository: ExportImageRepository,
        plan: MovieExportPlan,
        composition: ExportCompositionMode,
        background: ExportBackground,
        destination: URL
    ) {
        guard window?.isVisible == true else { return }
        let composer = ExportFrameComposer(
            outputSize: plan.outputSize,
            composition: composition,
            transition: plan.transition,
            background: background,
            sourceImage: repository.image(sourceIndex:localTime:)
        )
        statusLabel.stringValue = L10n.text("export.exporting")
        cancellation = MovieExportCoordinator(composer: composer).start(
            plan: plan,
            destination: destination,
            progress: { [weak self] value in
                Task { @MainActor [weak self] in
                    self?.progressIndicator.doubleValue = value
                }
            },
            completion: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.cancellation = nil
                    switch result {
                    case .success:
                        self.exportedURL = destination
                        self.progressIndicator.doubleValue = 1
                        self.revealButton.isHidden = false
                        self.setExporting(false, status: L10n.text("export.complete"))
                        self.cancelButton.title = L10n.text("export.close")
                    case .failure(.cancelled):
                        self.setExporting(false, status: L10n.text("export.cancelled"))
                    case .failure(let error):
                        self.setExporting(false, status: "Export failed: \(error)")
                    }
                }
            }
        )
    }

    @objc private func cancelOrClose(_ sender: Any?) {
        if let cancellation {
            cancellation.cancel()
            self.cancellation = nil
        } else {
            close()
        }
    }

    @objc private func revealOutput(_ sender: Any?) {
        guard let exportedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
    }

    private var selectedOutputSize: CGSize {
        switch preset.indexOfSelectedItem {
        case 0: CGSize(width: 854, height: 480)
        case 2: CGSize(width: 1_920, height: 1_080)
        default: CGSize(width: 1_280, height: 720)
        }
    }

    private func validateDurations() -> Bool {
        staticDuration.doubleValue > 0 &&
            (animationPolicy.indexOfSelectedItem != 2 || maximumDuration.doubleValue > 0)
    }

    private func updateControlState() {
        maximumDuration.isEnabled = animationPolicy.indexOfSelectedItem == 2
        chooseBackgroundButton.isEnabled = cancellation == nil
        exportButton.isEnabled = cancellation == nil && validateDurations()
    }

    private func setExporting(_ exporting: Bool, status: String) {
        statusLabel.stringValue = status
        exportButton.isEnabled = !exporting && validateDurations()
        sourceScope.isEnabled = !exporting
        preset.isEnabled = !exporting
        composition.isEnabled = !exporting
        transition.isEnabled = !exporting
        staticDuration.isEnabled = !exporting
        animationPolicy.isEnabled = !exporting
        maximumDuration.isEnabled = !exporting && animationPolicy.indexOfSelectedItem == 2
        background.isEnabled = !exporting
        chooseBackgroundButton.isEnabled = !exporting
        cancelButton.title = exporting ? L10n.text("export.cancel") : cancelButton.title
    }

    private func notifyCloseOnce() {
        guard !didNotifyClose else { return }
        didNotifyClose = true
        onClose?()
    }
}
