import AppKit
import LightViewCore

@MainActor
final class ViewerWindowController: NSWindowController, NSUserInterfaceValidations, NSWindowDelegate {
    let session: ViewingSession

    private let preferences: PreferencesStore
    private let canvas = ImageCanvasView()
    private let welcome = WelcomeViewController()
    private let container = DropContainerView()
    private let onOpenPanelRequest: () -> Void
    private let systemIntegration: SystemIntegration
    private let onShowInformation: (ImageInformationModel) -> Void
    private var showsInformationAfterNextPresentation = false

    init(
        session: ViewingSession,
        preferences: PreferencesStore,
        systemIntegration: SystemIntegration,
        onOpenPanelRequest: @escaping () -> Void,
        onShowInformation: @escaping (ImageInformationModel) -> Void
    ) {
        self.session = session
        self.preferences = preferences
        self.systemIntegration = systemIntegration
        self.onOpenPanelRequest = onOpenPanelRequest
        self.onShowInformation = onShowInformation
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.delegate = self
        window.center()
        window.title = "LightView"
        container.onOpenURL = { [weak self] url in self?.open(url) }
        window.contentView = container
        welcome.onOpen = { [weak self] in self?.onOpenPanelRequest() }
        session.navigationWraps = preferences.navigationWraps
        session.neighborPreloadCount = preferences.preloadLevel.neighborCount
        session.onStateChange = { [weak self] state in self?.present(state) }
        canvas.setMode(preferences.initialZoomMode.viewportMode)
        applyPreferences()
        showWelcome()
    }

    required init?(coder: NSCoder) { nil }

    func open(_ url: URL) {
        do {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let catalog = try FolderCatalog(directoryURL: url, sort: preferences.catalogSort)
                guard let first = catalog.entries.first else {
                    throw ImageLoadError.decodeFailed("No supported images in this folder")
                }
                session.catalog = catalog
                session.open(first.url, targetPixelSize: decodeTargetSize)
            } else {
                session.catalog = try? FolderCatalog(
                    directoryURL: url.deletingLastPathComponent(),
                    sort: preferences.catalogSort
                )
                session.open(url, targetPixelSize: decodeTargetSize)
            }
        } catch let error as ImageLoadError {
            present(.failed(url: url, error: error, generation: session.generation))
        } catch {
            present(.failed(url: url, error: .decodeFailed(error.localizedDescription), generation: session.generation))
        }
    }

    func showWelcome() {
        canvas.asset = nil
        embed(welcome.view)
        window?.title = "LightView"
    }

    @objc func previousImage(_ sender: Any?) { session.navigate(.previous) }
    @objc func nextImage(_ sender: Any?) { session.navigate(.next) }
    @objc func firstImage(_ sender: Any?) {
        if let entry = session.catalog?.entries.first { session.open(entry.url, targetPixelSize: decodeTargetSize) }
    }
    @objc func lastImage(_ sender: Any?) {
        if let entry = session.catalog?.entries.last { session.open(entry.url, targetPixelSize: decodeTargetSize) }
    }
    @objc func zoomIn(_ sender: Any?) { canvas.zoom(by: preferences.zoomStep) }
    @objc func zoomOut(_ sender: Any?) { canvas.zoom(by: 1 / preferences.zoomStep) }
    @objc func fitToWindow(_ sender: Any?) { canvas.setMode(.fit) }
    @objc func fillWindow(_ sender: Any?) { canvas.setMode(.fill) }
    @objc func actualSize(_ sender: Any?) { canvas.setMode(.actualSize) }
    @objc func rotateLeft(_ sender: Any?) { canvas.rotate(by: -90) }
    @objc func rotateRight(_ sender: Any?) { canvas.rotate(by: 90) }
    @objc func flipHorizontal(_ sender: Any?) { canvas.viewportState.isFlippedHorizontally.toggle() }
    @objc func flipVertical(_ sender: Any?) { canvas.viewportState.isFlippedVertically.toggle() }
    @objc func toggleViewerFullScreen(_ sender: Any?) { window?.toggleFullScreen(sender) }
    @objc func reloadImage(_ sender: Any?) { session.reload(targetPixelSize: decodeTargetSize) }
    @objc func revealImageInFinder(_ sender: Any?) {
        guard let url = session.currentURL else { return }
        systemIntegration.revealInFinder(url)
    }
    @objc func openImageWith(_ sender: Any?) {
        guard let url = session.currentURL else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.prompt = "Open With"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let applicationURL = panel.url,
              applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return }
        systemIntegration.openWith(url, applicationURL: applicationURL)
    }
    @objc func showImageInformation(_ sender: Any?) {
        guard let url = session.currentURL, let asset = session.currentAsset else { return }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        onShowInformation(ImageInformationModel(
            url: url,
            format: asset.format,
            frameCount: asset.frameCount,
            metadata: asset.metadata,
            creationDate: values?.creationDate,
            modificationDate: values?.contentModificationDate
        ))
    }

    func showImageInformationWhenReady() {
        guard session.currentAsset == nil else {
            showImageInformation(nil)
            return
        }
        showsInformationAfterNextPresentation = true
    }
    override func cancelOperation(_ sender: Any?) {
        guard window?.styleMask.contains(.fullScreen) == false else { return }
        close()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        refreshForDisplayChange()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        window?.colorSpace = window?.screen?.colorSpace
        refreshForDisplayChange()
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let imageActions: Set<Selector> = [
            #selector(previousImage(_:)), #selector(nextImage(_:)), #selector(firstImage(_:)),
            #selector(lastImage(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)),
            #selector(fitToWindow(_:)), #selector(fillWindow(_:)), #selector(actualSize(_:)),
            #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(flipHorizontal(_:)),
            #selector(flipVertical(_:)), #selector(reloadImage(_:)),
            #selector(revealImageInFinder(_:)), #selector(openImageWith(_:)),
            #selector(showImageInformation(_:)),
        ]
        guard let action = item.action else { return true }
        return imageActions.contains(action) ? session.currentAsset != nil : true
    }

    private var decodeTargetSize: CGSize {
        let size = canvas.bounds.size == .zero ? CGSize(width: 1_280, height: 800) : canvas.bounds.size
        let scale = window?.backingScaleFactor ?? 1
        return DisplayRasterState(
            logicalViewportSize: size,
            backingScale: scale,
            imageSpaceCenter: .zero
        ).targetPixelSize
    }

    private func refreshForDisplayChange() {
        canvas.layer?.contentsScale = window?.backingScaleFactor ?? 1
        guard session.currentURL != nil else { return }
        session.reload(targetPixelSize: decodeTargetSize)
    }

    private func present(_ state: ViewingState) {
        switch state {
        case .empty:
            showWelcome()
        case .loading(let url, _):
            window?.title = "Loading \(url.lastPathComponent)…"
        case .presenting(let url, let asset, _):
            canvas.asset = asset
            embed(canvas)
            window?.title = title(for: url)
            window?.makeFirstResponder(canvas)
            if showsInformationAfterNextPresentation {
                showsInformationAfterNextPresentation = false
                showImageInformation(nil)
            }
        case .failed(let url, let error, _):
            showsInformationAfterNextPresentation = false
            showWelcome()
            window?.title = "Couldn’t open \(url.lastPathComponent)"
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t Open Image"
            alert.informativeText = String(describing: error)
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    private func title(for url: URL) -> String {
        guard let catalog = session.catalog, let index = catalog.index(of: url) else { return url.lastPathComponent }
        return "\(url.lastPathComponent) — \(index + 1) / \(catalog.entries.count)"
    }

    func applyPreferences() {
        session.navigationWraps = preferences.navigationWraps
        session.neighborPreloadCount = preferences.preloadLevel.neighborCount
        canvas.viewerBackgroundColor = preferences.viewerBackground.color(
            customHex: preferences.customBackgroundColorHex
        )
    }

    func setBackgroundAsset(_ asset: RasterAsset?) {
        canvas.backgroundAsset = asset
    }

    private func embed(_ view: NSView) {
        if container.subviews.first === view { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

private extension ViewerBackgroundPreference {
    func color(customHex: String?) -> NSColor {
        switch self {
        case .black, .customImage: .black
        case .darkGray: NSColor(calibratedWhite: 0.12, alpha: 1)
        case .white: .white
        case .customColor: NSColor(lightViewHex: customHex) ?? .black
        }
    }
}

private extension InitialZoomMode {
    var viewportMode: ViewportMode {
        switch self {
        case .fit: .fit
        case .fill: .fill
        case .actualSize: .actualSize
        }
    }
}

@MainActor
private final class DropContainerView: NSView {
    var onOpenURL: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let string = sender.draggingPasteboard.string(forType: .fileURL),
              let url = URL(string: string) else { return false }
        onOpenURL?(url)
        return true
    }
}
