import AppKit
import LightViewCore

@MainActor
final class ViewerWindowController: NSWindowController, NSUserInterfaceValidations {
    let session: ViewingSession

    private let preferences: PreferencesStore
    private let canvas = ImageCanvasView()
    private let welcome = WelcomeViewController()
    private let container = DropContainerView()
    private let onOpenPanelRequest: () -> Void

    init(session: ViewingSession, preferences: PreferencesStore, onOpenPanelRequest: @escaping () -> Void) {
        self.session = session
        self.preferences = preferences
        self.onOpenPanelRequest = onOpenPanelRequest
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.center()
        window.title = "LightView"
        container.onOpenURL = { [weak self] url in self?.open(url) }
        window.contentView = container
        welcome.onOpen = { [weak self] in self?.onOpenPanelRequest() }
        session.navigationWraps = preferences.navigationWraps
        session.neighborPreloadCount = preferences.preloadLevel.neighborCount
        session.onStateChange = { [weak self] state in self?.present(state) }
        showWelcome()
    }

    required init?(coder: NSCoder) { nil }

    func open(_ url: URL) {
        do {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let catalog = try FolderCatalog(directoryURL: url)
                guard let first = catalog.entries.first else {
                    throw ImageLoadError.decodeFailed("No supported images in this folder")
                }
                session.catalog = catalog
                session.open(first.url, targetPixelSize: decodeTargetSize)
            } else {
                session.catalog = try? FolderCatalog(directoryURL: url.deletingLastPathComponent())
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
    override func cancelOperation(_ sender: Any?) {
        guard window?.styleMask.contains(.fullScreen) == false else { return }
        close()
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let imageActions: Set<Selector> = [
            #selector(previousImage(_:)), #selector(nextImage(_:)), #selector(firstImage(_:)),
            #selector(lastImage(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)),
            #selector(fitToWindow(_:)), #selector(fillWindow(_:)), #selector(actualSize(_:)),
            #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(flipHorizontal(_:)),
            #selector(flipVertical(_:)),
        ]
        guard let action = item.action else { return true }
        return imageActions.contains(action) ? session.currentAsset != nil : true
    }

    private var decodeTargetSize: CGSize {
        let size = canvas.bounds.size == .zero ? CGSize(width: 1_280, height: 800) : canvas.bounds.size
        let scale = window?.backingScaleFactor ?? 1
        return CGSize(width: size.width * scale, height: size.height * scale)
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
        case .failed(let url, let error, _):
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
