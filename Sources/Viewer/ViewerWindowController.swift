import AppKit
import LightViewCore

@MainActor
final class ViewerWindowController: NSWindowController, NSUserInterfaceValidations, NSWindowDelegate {
    let session: ViewingSession

    private let preferences: PreferencesStore
    private let canvas = ImageCanvasView()
    private let welcome = WelcomeViewController()
    private let container = DropContainerView()
    private lazy var viewerToolbar = ViewerToolbarView(target: self)
    private let onOpenPanelRequest: () -> Void
    private let systemIntegration: SystemIntegration
    private let folderAccessProvider: any FolderAccessProvider
    private let onFolderAuthorizationRequest: (URL) -> AccessLease?
    private let onShowInformation: (ImageInformationModel) -> Void
    private let onClose: (ViewerWindowController) -> Void
    private var showsInformationAfterNextPresentation = false
    private var animationWorker: AnimationPlaybackWorker?
    private var animationCanvasPixelSize: CGSize?
    private var animationTimer: Timer?
    private var animationIsPlaying = false
    private var animationSpeed = 1.0
    private var resumesAnimationAfterOcclusion = false
    private var movieExportWindowController: MovieExportWindowController?
    private var currentImageAccessLease: AccessLease?
    private var folderAccessLease: AccessLease?
    private var folderNavigationDenied = false
    private var exifOverlayRequested = false
    private lazy var slideshowController = SlideshowController { [weak self] direction in
        MainActor.assumeIsolated { self?.session.navigate(direction) ?? false }
    }

    init(
        session: ViewingSession,
        preferences: PreferencesStore,
        systemIntegration: SystemIntegration,
        folderAccessProvider: any FolderAccessProvider,
        onOpenPanelRequest: @escaping () -> Void,
        onFolderAuthorizationRequest: @escaping (URL) -> AccessLease?,
        onShowInformation: @escaping (ImageInformationModel) -> Void,
        onClose: @escaping (ViewerWindowController) -> Void
    ) {
        self.session = session
        self.preferences = preferences
        self.systemIntegration = systemIntegration
        self.folderAccessProvider = folderAccessProvider
        self.onOpenPanelRequest = onOpenPanelRequest
        self.onFolderAuthorizationRequest = onFolderAuthorizationRequest
        self.onShowInformation = onShowInformation
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("LightView.ViewerWindow") {
            window.center()
        }
        window.setFrameAutosaveName("LightView.ViewerWindow")
        window.title = "LightView"
        container.onOpenURL = { [weak self] url in self?.open(url) }
        canvas.onFullResolutionRequest = { [weak self] in self?.loadCurrentImageAtFullResolution() }
        canvas.onPresentationChange = { [weak self] in self?.updatePresentationChrome() }
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
        slideshowController.manualNavigationOccurred()
        do {
            folderNavigationDenied = false
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                let lease = try folderAccessProvider.authorizeFolder(at: url)
                let catalog = try FolderCatalog(directoryURL: url, sort: preferences.catalogSort)
                guard let first = catalog.entries.first else {
                    throw ImageLoadError.decodeFailed("No supported images in this folder")
                }
                replaceFolderLease(with: lease)
                replaceImageLease(with: nil)
                session.catalog = catalog
                session.open(first.url, targetPixelSize: decodeTargetSize)
            } else {
                let imageLease = try folderAccessProvider.accessImage(at: url)
                let folder = url.deletingLastPathComponent()
                let restoredFolderLease = try folderAccessProvider.restorePersistedAccess(to: folder)
                replaceImageLease(with: imageLease)
                replaceFolderLease(with: restoredFolderLease)
                session.catalog = restoredFolderLease.flatMap { _ in
                    try? FolderCatalog(directoryURL: folder, sort: preferences.catalogSort)
                }
                session.open(url, targetPixelSize: decodeTargetSize)
            }
        } catch let error as ImageLoadError {
            present(.failed(url: url, error: error, generation: session.generation))
        } catch {
            present(.failed(url: url, error: .decodeFailed(error.localizedDescription), generation: session.generation))
        }
    }

    func showWelcome() {
        slideshowController.stop()
        stopAnimation()
        canvas.clearImage()
        canvas.setEXIFOverlay(rows: nil)
        embed(welcome.view)
        window?.title = "LightView"
    }

    func showEmptyCanvas() {
        slideshowController.stop()
        stopAnimation()
        canvas.clearImage()
        canvas.setEXIFOverlay(rows: nil)
        embed(canvas)
        window?.title = "LightView"
        window?.makeFirstResponder(canvas)
    }

    @objc func previousImage(_ sender: Any?) { navigateManually(.previous) }
    @objc func nextImage(_ sender: Any?) { navigateManually(.next) }
    @objc func firstImage(_ sender: Any?) {
        slideshowController.manualNavigationOccurred()
        if let entry = session.catalog?.entries.first { session.open(entry.url, targetPixelSize: decodeTargetSize) }
    }
    @objc func lastImage(_ sender: Any?) {
        slideshowController.manualNavigationOccurred()
        if let entry = session.catalog?.entries.last { session.open(entry.url, targetPixelSize: decodeTargetSize) }
    }
    @objc func zoomIn(_ sender: Any?) { canvas.zoom(by: preferences.zoomStep) }
    @objc func zoomOut(_ sender: Any?) { canvas.zoom(by: 1 / preferences.zoomStep) }
    @objc func fitToWindow(_ sender: Any?) { canvas.setMode(.fit) }
    @objc func fillWindow(_ sender: Any?) { canvas.setMode(.fill) }
    @objc func actualSize(_ sender: Any?) { canvas.setMode(.actualSize) }
    @objc func toggleEXIFOverlay(_ sender: Any?) {
        guard !currentEXIFRows.isEmpty else { return }
        exifOverlayRequested.toggle()
        updatePresentationChrome()
    }
    @objc func rotateLeft(_ sender: Any?) { canvas.rotate(by: -90) }
    @objc func rotateRight(_ sender: Any?) { canvas.rotate(by: 90) }
    @objc func flipHorizontal(_ sender: Any?) { canvas.viewportState.isFlippedHorizontally.toggle() }
    @objc func flipVertical(_ sender: Any?) { canvas.viewportState.isFlippedVertically.toggle() }
    @objc func toggleViewerFullScreen(_ sender: Any?) { window?.toggleFullScreen(sender) }
    @objc func reloadImage(_ sender: Any?) { session.reload(targetPixelSize: decodeTargetSize) }
    @objc func toggleAnimationPlayback(_ sender: Any?) {
        performAnimationCommand(.toggle)
    }
    @objc func previousAnimationFrame(_ sender: Any?) {
        stopAnimationTimer()
        performAnimationCommand(.stepBackward)
    }
    @objc func nextAnimationFrame(_ sender: Any?) {
        stopAnimationTimer()
        performAnimationCommand(.stepForward)
    }
    @objc func decreaseAnimationSpeed(_ sender: Any?) {
        setAnimationSpeed(animationSpeed / 2)
    }
    @objc func normalAnimationSpeed(_ sender: Any?) {
        setAnimationSpeed(1)
    }
    @objc func increaseAnimationSpeed(_ sender: Any?) {
        setAnimationSpeed(animationSpeed * 2)
    }
    @objc func toggleSlideshow(_ sender: Any?) {
        if slideshowController.state == .stopped {
            startSlideshow(direction: .next)
        } else {
            slideshowController.stop()
        }
    }
    @objc func startReverseSlideshow(_ sender: Any?) {
        startSlideshow(direction: .previous)
    }
    @objc func toggleSlideshowPause(_ sender: Any?) {
        switch slideshowController.state {
        case .running: slideshowController.pause()
        case .paused: slideshowController.resume()
        case .stopped: break
        }
    }
    @objc func revealImageInFinder(_ sender: Any?) {
        guard let url = session.currentURL else { return }
        systemIntegration.revealInFinder(url)
    }
    @objc func openImageWith(_ sender: Any?) {
        guard let url = session.currentURL else { return }
        let restoresSlideshow = suspendSlideshowForModalPanel()
        defer { restoreSlideshowAfterModalPanel(ifNeeded: restoresSlideshow) }
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
    @objc func exportMP4(_ sender: Any?) {
        guard let currentURL = session.currentURL, session.currentAsset != nil else { return }
        if let movieExportWindowController {
            movieExportWindowController.showWindow(sender)
            movieExportWindowController.window?.makeKeyAndOrderFront(sender)
            return
        }
        let suspendedSlideshow = suspendSlideshowForModalPanel()
        let folderURLs = session.catalog?.entries.map(\.url) ?? [currentURL]
        let controller = MovieExportWindowController(currentURL: currentURL, folderURLs: folderURLs)
        controller.onClose = { [weak self, weak controller] in
            guard let self else { return }
            if self.movieExportWindowController === controller {
                self.movieExportWindowController = nil
            }
            self.restoreSlideshowAfterModalPanel(ifNeeded: suspendedSlideshow)
        }
        movieExportWindowController = controller
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
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

    func windowDidBecomeKey(_ notification: Notification) {
        bindViewerMenuTargets(in: NSApplication.shared.mainMenu)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        if window?.occlusionState.contains(.visible) == true {
            if resumesAnimationAfterOcclusion {
                resumesAnimationAfterOcclusion = false
                performAnimationCommand(.play)
            } else {
                startAnimationTimerIfVisible()
            }
        } else {
            if preferences.animationEnergySaving, animationIsPlaying {
                resumesAnimationAfterOcclusion = true
                performAnimationCommand(.pause)
            }
            stopAnimationTimer()
        }
    }

    func windowWillClose(_ notification: Notification) {
        slideshowController.stop()
        stopAnimation()
        onClose(self)
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let imageActions: Set<Selector> = [
            #selector(previousImage(_:)), #selector(nextImage(_:)), #selector(firstImage(_:)),
            #selector(lastImage(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)),
            #selector(fitToWindow(_:)), #selector(fillWindow(_:)), #selector(actualSize(_:)),
            #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(flipHorizontal(_:)),
            #selector(flipVertical(_:)), #selector(reloadImage(_:)),
            #selector(revealImageInFinder(_:)), #selector(openImageWith(_:)),
            #selector(showImageInformation(_:)), #selector(exportMP4(_:)),
        ]
        let animationActions: Set<Selector> = [
            #selector(toggleAnimationPlayback(_:)), #selector(previousAnimationFrame(_:)),
            #selector(nextAnimationFrame(_:)), #selector(decreaseAnimationSpeed(_:)),
            #selector(normalAnimationSpeed(_:)), #selector(increaseAnimationSpeed(_:)),
        ]
        let slideshowActions: Set<Selector> = [
            #selector(toggleSlideshow(_:)), #selector(startReverseSlideshow(_:)),
            #selector(toggleSlideshowPause(_:)),
        ]
        guard let action = item.action else { return true }
        if action == #selector(toggleAnimationPlayback(_:)), let menuItem = item as? NSMenuItem {
            menuItem.title = animationIsPlaying ? "Pause Animation" : "Play Animation"
        }
        if animationActions.contains(action) { return animationWorker != nil }
        if action == #selector(toggleEXIFOverlay(_:)) {
            let hasEXIF = !currentEXIFRows.isEmpty
            if let menuItem = item as? NSMenuItem {
                menuItem.title = exifOverlayRequested ? "Hide EXIF Overlay" : "Show EXIF Overlay"
                menuItem.state = exifOverlayRequested && hasEXIF ? .on : .off
            }
            return hasEXIF
        }
        if action == #selector(toggleSlideshow(_:)), let menuItem = item as? NSMenuItem {
            menuItem.title = slideshowController.state == .stopped ? "Start Slideshow" : "Stop Slideshow"
            menuItem.state = slideshowController.activeDirection == .next ? .on : .off
        }
        if action == #selector(startReverseSlideshow(_:)), let menuItem = item as? NSMenuItem {
            menuItem.state = slideshowController.activeDirection == .previous ? .on : .off
        }
        if action == #selector(toggleSlideshowPause(_:)), let menuItem = item as? NSMenuItem {
            menuItem.title = slideshowController.state == .paused ? "Resume Slideshow" : "Pause Slideshow"
            menuItem.state = slideshowController.state == .paused ? .on : .off
        }
        if slideshowActions.contains(action) {
            if action == #selector(toggleSlideshowPause(_:)) {
                return slideshowController.state != .stopped
            }
            return (session.catalog?.entries.count ?? 0) > 1 && session.currentAsset != nil
        }
        if action == #selector(previousImage(_:)) || action == #selector(nextImage(_:)) {
            guard session.currentAsset != nil, !folderNavigationDenied else { return false }
            return session.catalog == nil || (session.catalog?.entries.count ?? 0) > 1
        }
        if action == #selector(firstImage(_:)) || action == #selector(lastImage(_:)) {
            return (session.catalog?.entries.count ?? 0) > 1 && session.currentAsset != nil
        }
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
            stopAnimation()
            canvas.setEXIFOverlay(rows: nil)
            window?.title = "Loading \(url.lastPathComponent)…"
            viewerToolbar.refreshAvailability(using: self)
        case .presenting(_, let asset, _):
            stopAnimation()
            resizeWindowIfNeeded(for: asset)
            switch asset {
            case .raster(let raster):
                canvas.asset = raster
            case .animation(let animation):
                present(animation: animation)
            case .vector:
                canvas.clearImage()
            }
            embed(canvas)
            updatePresentationChrome()
            window?.makeFirstResponder(canvas)
            if showsInformationAfterNextPresentation {
                showsInformationAfterNextPresentation = false
                showImageInformation(nil)
            }
        case .failed(let url, let error, _):
            showsInformationAfterNextPresentation = false
            canvas.setEXIFOverlay(rows: nil)
            showWelcome()
            window?.title = "Couldn’t open \(url.lastPathComponent)"
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.text("error.openImage")
            alert.informativeText = error.userFacingDescription
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    private var currentEXIFRows: [EXIFInformationRow] {
        EXIFInformationFormatter.rows(for: session.currentAsset?.metadata.exif)
    }

    private func updatePresentationChrome() {
        guard let url = session.currentURL, let asset = session.currentAsset else {
            canvas.setEXIFOverlay(rows: nil)
            viewerToolbar.refreshAvailability(using: self)
            return
        }
        let catalog = session.catalog
        let index = catalog?.index(of: url)
        let scale = canvas.scaleForPresentation(of: asset.metadata.pixelSize) ?? 1
        window?.title = ViewerTitleFormatter.title(
            url: url,
            format: asset.format,
            metadata: asset.metadata,
            frameCount: asset.frameCount,
            index: index,
            totalCount: catalog?.entries.count,
            presentationScale: scale,
            rotationDegrees: canvas.viewportState.rotationDegrees
        )
        canvas.setEXIFOverlay(rows: exifOverlayRequested ? currentEXIFRows : nil)
        viewerToolbar.refreshAvailability(using: self)
    }

    private func loadCurrentImageAtFullResolution() {
        guard let url = session.currentURL,
              case .raster = session.currentAsset else { return }
        session.open(url, targetPixelSize: decodeTargetSize, requiresFullResolution: true)
    }

    private func resizeWindowIfNeeded(for asset: DisplayAsset) {
        guard preferences.autoResizesWindow, let window, let screen = window.screen ?? NSScreen.main else { return }
        let imageSize: CGSize
        switch asset {
        case .raster(let raster): imageSize = raster.originalPixelSize
        case .animation(let animation): imageSize = animation.canvasPixelSize
        case .vector(let vector): imageSize = vector.intrinsicPixelSize ?? .zero
        }
        let available = CGSize(
            width: max(320, screen.visibleFrame.width - 80),
            height: max(240, screen.visibleFrame.height - 100)
        )
        guard let contentSize = ViewportGeometry.windowContentSize(
            imageSize: imageSize,
            availableSize: available,
            minimumSize: CGSize(width: 320, height: 240)
        ) else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(contentSize)
        window.setFrameTopLeftPoint(topLeft)
        window.setFrame(window.constrainFrameRect(window.frame, to: screen), display: true)
    }

    func applyPreferences() {
        session.navigationWraps = preferences.navigationWraps
        session.neighborPreloadCount = preferences.preloadLevel.neighborCount
        canvas.viewerBackgroundColor = preferences.viewerBackground.color(
            customHex: preferences.customBackgroundColorHex
        )
        viewerToolbar.isHidden = !preferences.showsViewerToolbar
    }

    func setBackgroundAsset(_ asset: RasterAsset?) {
        canvas.backgroundAsset = asset
    }

    func suspendSlideshowForModalPanel() -> Bool {
        guard slideshowController.state == .running else { return false }
        slideshowController.pause()
        return true
    }

    func restoreSlideshowAfterModalPanel(ifNeeded shouldRestore: Bool) {
        guard shouldRestore, slideshowController.state == .paused else { return }
        slideshowController.resume()
    }

    func stopSlideshow() {
        slideshowController.stop()
    }

    private func navigateManually(_ direction: CatalogDirection) {
        slideshowController.manualNavigationOccurred()
        if session.catalog == nil, !folderNavigationDenied,
           let currentURL = session.currentURL {
            let folder = currentURL.deletingLastPathComponent()
            guard let lease = onFolderAuthorizationRequest(folder) else {
                folderNavigationDenied = true
                showFolderAccessCancelledMessage()
                return
            }
            do {
                let catalog = try FolderCatalog(directoryURL: folder, sort: preferences.catalogSort)
                replaceFolderLease(with: lease)
                session.catalog = catalog
            } catch {
                lease.end()
                showFolderAccessCancelledMessage()
                return
            }
        }
        session.navigate(direction)
    }

    private func replaceImageLease(with lease: AccessLease?) {
        currentImageAccessLease?.end()
        currentImageAccessLease = lease
    }

    private func replaceFolderLease(with lease: AccessLease?) {
        folderAccessLease?.end()
        folderAccessLease = lease
    }

    private func showFolderAccessCancelledMessage() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.text("folderAccess.cancelledTitle")
        alert.informativeText = L10n.text("folderAccess.cancelledMessage")
        if let window { alert.beginSheetModal(for: window) }
    }

    private func startSlideshow(direction: CatalogDirection) {
        guard (session.catalog?.entries.count ?? 0) > 1, session.currentAsset != nil else { return }
        try? slideshowController.start(direction: direction, interval: preferences.slideshowInterval)
    }

    func bindViewerMenuTargets(in menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items {
            if let action = item.action, Self.viewerMenuActions.contains(action) {
                item.target = self
            }
            bindViewerMenuTargets(in: item.submenu)
        }
    }

    func releaseViewerMenuTargets(in menu: NSMenu?) {
        guard let menu else { return }
        for item in menu.items {
            if item.target === self {
                item.target = nil
            }
            releaseViewerMenuTargets(in: item.submenu)
        }
    }

    private static let viewerMenuActions: Set<Selector> = [
        #selector(previousImage(_:)), #selector(nextImage(_:)), #selector(firstImage(_:)),
        #selector(lastImage(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)),
        #selector(fitToWindow(_:)), #selector(fillWindow(_:)), #selector(actualSize(_:)),
        #selector(toggleEXIFOverlay(_:)),
        #selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(flipHorizontal(_:)),
        #selector(flipVertical(_:)), #selector(toggleViewerFullScreen(_:)),
        #selector(reloadImage(_:)), #selector(revealImageInFinder(_:)),
        #selector(openImageWith(_:)), #selector(showImageInformation(_:)), #selector(exportMP4(_:)),
        #selector(toggleAnimationPlayback(_:)), #selector(previousAnimationFrame(_:)),
        #selector(nextAnimationFrame(_:)), #selector(decreaseAnimationSpeed(_:)),
        #selector(normalAnimationSpeed(_:)), #selector(increaseAnimationSpeed(_:)), #selector(toggleSlideshow(_:)),
        #selector(startReverseSlideshow(_:)), #selector(toggleSlideshowPause(_:)),
    ]

    private func present(animation: AnimationAsset) {
        let worker = AnimationPlaybackWorker(
            provider: animation.provider,
            cacheByteLimit: 256 * 1_024 * 1_024
        )
        animationWorker = worker
        animationCanvasPixelSize = animation.canvasPixelSize
        animationIsPlaying = true
        animationSpeed = 1
        worker.perform(.play, at: ProcessInfo.processInfo.systemUptime) { [weak self, weak worker] result in
            Task { @MainActor in self?.handleAnimationResult(result, from: worker) }
        }
    }

    private func renderAnimationFrame(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let worker = animationWorker else { return }
        worker.advance(to: timestamp) { [weak self, weak worker] result in
            Task { @MainActor in self?.handleAnimationResult(result, from: worker) }
        }
    }

    private func setAnimationSpeed(_ speed: Double) {
        performAnimationCommand(.setSpeed(speed))
    }

    private func performAnimationCommand(_ command: AnimationPlaybackCommand) {
        guard let worker = animationWorker else { return }
        worker.perform(command, at: ProcessInfo.processInfo.systemUptime) { [weak self, weak worker] result in
            Task { @MainActor in self?.handleAnimationResult(result, from: worker) }
        }
    }

    private func handleAnimationResult(
        _ result: Result<AnimationPlaybackSnapshot, Error>,
        from worker: AnimationPlaybackWorker?
    ) {
        guard let worker, worker === animationWorker, let animationCanvasPixelSize else { return }
        switch result {
        case .success(let snapshot):
            animationIsPlaying = snapshot.isPlaying
            animationSpeed = snapshot.speed
            canvas.setAnimationFrame(snapshot.frame, canvasPixelSize: animationCanvasPixelSize)
            if snapshot.isComplete || !snapshot.isPlaying {
                stopAnimationTimer()
            } else {
                startAnimationTimerIfVisible()
            }
        case .failure(let error):
            stopAnimation()
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.text("error.playAnimation")
            alert.informativeText = error.localizedDescription
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    private func startAnimationTimerIfVisible() {
        guard animationTimer == nil,
              animationIsPlaying,
              animationWorker != nil,
              window?.occlusionState.contains(.visible) == true else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderAnimationFrame() }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func stopAnimation() {
        stopAnimationTimer()
        animationWorker?.cancel()
        animationWorker = nil
        animationCanvasPixelSize = nil
        animationIsPlaying = false
        animationSpeed = 1
        resumesAnimationAfterOcclusion = false
    }

    private func embed(_ view: NSView) {
        if container.subviews.first === view {
            viewerToolbar.refreshAvailability(using: self)
            return
        }
        container.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        guard view === canvas else { return }
        viewerToolbar.translatesAutoresizingMaskIntoConstraints = false
        viewerToolbar.isHidden = !preferences.showsViewerToolbar
        container.addSubview(viewerToolbar)
        NSLayoutConstraint.activate([
            viewerToolbar.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            viewerToolbar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        viewerToolbar.refreshAvailability(using: self)
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
