import AppKit
import LightViewCore

@MainActor
final class AppCoordinator: NSObject {
    private let preferences = PreferencesStore()
    private let pipeline = ImageLoadPipeline()
    private let systemIntegration = SystemIntegration(workspace: AppKitSystemWorkspace())
    private var windowControllers: [ViewerWindowController] = []
    private var preferencesWindowController: PreferencesWindowController?
    private var informationWindowController: ImageInfoWindowController?
    private let openRecentMenu = NSMenu(title: "Open Recent")
    private var backgroundCancellation: DecodeCancellation?

    override init() {
        super.init()
        buildMainMenu()
        applyPreferences()
    }

    func makeWindowController() -> ViewerWindowController {
        let controller = ViewerWindowController(
            session: ViewingSession(loader: pipeline),
            preferences: preferences,
            systemIntegration: systemIntegration,
            onOpenPanelRequest: { [weak self] in self?.showOpenPanel(nil) },
            onShowInformation: { [weak self] model in self?.showInformation(model) },
            onClose: { [weak self] controller in self?.viewerWindowDidClose(controller) }
        )
        windowControllers.append(controller)
        return controller
    }

    func openEmptyWindow() { makeWindowController().showWindow(nil) }

    func open(_ url: URL) {
        let controller = windowControllers.first(where: { $0.session.currentURL == nil }) ?? makeWindowController()
        controller.showWindow(nil)
        controller.open(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshOpenRecentMenu()
    }

    @objc func newWindow(_ sender: Any?) { openEmptyWindow() }

    @objc func showOpenPanel(_ sender: Any?) {
        let presentingController = windowControllers.first(where: { $0.window?.isKeyWindow == true })
        let restoresSlideshow = presentingController?.suspendSlideshowForModalPanel() == true
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else {
            presentingController?.restoreSlideshowAfterModalPanel(ifNeeded: restoresSlideshow)
            return
        }
        presentingController?.stopSlideshow()
        open(url)
    }

    @objc func showWelcomeGuide(_ sender: Any?) {
        let controller = windowControllers.first ?? makeWindowController()
        controller.showWindow(nil)
        controller.showWelcome()
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            let controller = PreferencesWindowController(preferences: preferences)
            controller.onPreferencesChanged = { [weak self] in self?.applyPreferences() }
            preferencesWindowController = controller
        }
        preferencesWindowController?.showWindow(sender)
        preferencesWindowController?.window?.makeKeyAndOrderFront(sender)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url)
    }

    func showInformationForTesting(path: String) {
        let url = URL(fileURLWithPath: path)
        open(url)
        guard let controller = windowControllers.first(where: { $0.session.currentURL == url.standardizedFileURL }) else { return }
        controller.showImageInformationWhenReady()
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About LightView", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let preferencesItem = NSMenuItem(title: "Settings…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LightView", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        add(.newWindow, to: fileMenu, action: #selector(newWindow(_:)), target: self)
        add(.open, to: fileMenu, action: #selector(showOpenPanel(_:)), target: self)
        let openRecentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        openRecentItem.submenu = openRecentMenu
        fileMenu.addItem(openRecentItem)
        fileMenu.addItem(.separator())
        add(.closeWindow, to: fileMenu, action: #selector(NSWindow.performClose(_:)))
        add(.information, to: fileMenu, action: #selector(ViewerWindowController.showImageInformation(_:)))
        add(.openWith, to: fileMenu, action: #selector(ViewerWindowController.openImageWith(_:)))
        add(.reload, to: fileMenu, action: #selector(ViewerWindowController.reloadImage(_:)))
        add(.revealInFinder, to: fileMenu, action: #selector(ViewerWindowController.revealImageInFinder(_:)))
        fileMenu.addItem(.separator())
        add(.exportMP4, to: fileMenu, action: #selector(ViewerWindowController.exportMP4(_:)))
        append(fileMenu, titled: "File", to: main)

        let viewMenu = NSMenu(title: "View")
        add(.previous, to: viewMenu, action: #selector(ViewerWindowController.previousImage(_:)))
        add(.next, to: viewMenu, action: #selector(ViewerWindowController.nextImage(_:)))
        add(.first, to: viewMenu, action: #selector(ViewerWindowController.firstImage(_:)))
        add(.last, to: viewMenu, action: #selector(ViewerWindowController.lastImage(_:)))
        viewMenu.addItem(.separator())
        add(.zoomIn, to: viewMenu, action: #selector(ViewerWindowController.zoomIn(_:)))
        add(.zoomOut, to: viewMenu, action: #selector(ViewerWindowController.zoomOut(_:)))
        add(.fit, to: viewMenu, action: #selector(ViewerWindowController.fitToWindow(_:)))
        add(.fill, to: viewMenu, action: #selector(ViewerWindowController.fillWindow(_:)))
        add(.actualSize, to: viewMenu, action: #selector(ViewerWindowController.actualSize(_:)))
        viewMenu.addItem(.separator())
        add(.rotateLeft, to: viewMenu, action: #selector(ViewerWindowController.rotateLeft(_:)))
        add(.rotateRight, to: viewMenu, action: #selector(ViewerWindowController.rotateRight(_:)))
        add(.flipHorizontal, to: viewMenu, action: #selector(ViewerWindowController.flipHorizontal(_:)))
        add(.flipVertical, to: viewMenu, action: #selector(ViewerWindowController.flipVertical(_:)))
        add(.toggleFullScreen, to: viewMenu, action: #selector(ViewerWindowController.toggleViewerFullScreen(_:)))
        append(viewMenu, titled: "View", to: main)

        let animationMenu = NSMenu(title: "Animation")
        add(.togglePlayback, to: animationMenu, action: #selector(ViewerWindowController.toggleAnimationPlayback(_:)))
        animationMenu.addItem(.separator())
        add(.previousAnimationFrame, to: animationMenu, action: #selector(ViewerWindowController.previousAnimationFrame(_:)))
        add(.nextAnimationFrame, to: animationMenu, action: #selector(ViewerWindowController.nextAnimationFrame(_:)))
        animationMenu.addItem(.separator())
        add(.decreaseAnimationSpeed, to: animationMenu, action: #selector(ViewerWindowController.decreaseAnimationSpeed(_:)))
        add(.increaseAnimationSpeed, to: animationMenu, action: #selector(ViewerWindowController.increaseAnimationSpeed(_:)))
        append(animationMenu, titled: "Animation", to: main)

        let slideshowMenu = NSMenu(title: "Slideshow")
        add(.toggleSlideshow, to: slideshowMenu, action: #selector(ViewerWindowController.toggleSlideshow(_:)))
        add(.startReverseSlideshow, to: slideshowMenu, action: #selector(ViewerWindowController.startReverseSlideshow(_:)))
        slideshowMenu.addItem(.separator())
        add(.toggleSlideshowPause, to: slideshowMenu, action: #selector(ViewerWindowController.toggleSlideshowPause(_:)))
        append(slideshowMenu, titled: "Slideshow", to: main)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        append(windowMenu, titled: "Window", to: main)
        NSApplication.shared.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        let guide = NSMenuItem(title: "LightView Keyboard & Gestures", action: #selector(showWelcomeGuide(_:)), keyEquivalent: "?")
        guide.target = self
        helpMenu.addItem(guide)
        append(helpMenu, titled: "Help", to: main)
        NSApplication.shared.helpMenu = helpMenu
        NSApplication.shared.mainMenu = main
        refreshOpenRecentMenu()
    }

    private func append(_ menu: NSMenu, titled title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }

    private func add(_ identifier: CommandIdentifier, to menu: NSMenu, action: Selector, target: AnyObject? = nil) {
        let definition = CommandCatalog.definition(for: identifier)
        let item = NSMenuItem(title: definition.title, action: action, keyEquivalent: definition.keyEquivalent)
        item.keyEquivalentModifierMask = definition.modifiers.appKitFlags
        item.target = target
        menu.addItem(item)
    }

    private func showInformation(_ model: ImageInformationModel) {
        if let informationWindowController {
            informationWindowController.update(model: model)
        } else {
            informationWindowController = ImageInfoWindowController(model: model)
        }
        informationWindowController?.showWindow(nil)
        informationWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func viewerWindowDidClose(_ controller: ViewerWindowController) {
        controller.releaseViewerMenuTargets(in: NSApplication.shared.mainMenu)
        windowControllers.removeAll { $0 === controller }
        let replacement = windowControllers.first(where: { $0.window?.isKeyWindow == true })
            ?? windowControllers.last(where: { $0.window?.isVisible == true })
        replacement?.bindViewerMenuTargets(in: NSApplication.shared.mainMenu)
    }

    private func refreshOpenRecentMenu() {
        openRecentMenu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs.prefix(10) {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            openRecentMenu.addItem(item)
        }
        if openRecentMenu.items.isEmpty {
            let empty = NSMenuItem(title: "No Recent Items", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            openRecentMenu.addItem(empty)
        }
    }

    private func applyPreferences() {
        switch preferences.appearance {
        case .followSystem: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        windowControllers.forEach { $0.applyPreferences() }
        loadBackgroundImageIfNeeded()
    }

    private func loadBackgroundImageIfNeeded() {
        backgroundCancellation?.cancel()
        backgroundCancellation = nil
        guard preferences.viewerBackground == .customImage,
              let url = preferences.backgroundImageURL else {
            windowControllers.forEach { $0.setBackgroundAsset(nil) }
            return
        }
        let screen = NSScreen.main
        let logicalSize = screen?.frame.size ?? CGSize(width: 1_920, height: 1_080)
        let target = DisplayRasterState(
            logicalViewportSize: logicalSize,
            backingScale: screen?.backingScaleFactor ?? 1,
            imageSpaceCenter: .zero
        ).targetPixelSize
        let request = DecodeRequest(
            url: url,
            targetPixelSize: target,
            requiresFullResolution: false,
            generation: 0
        )
        backgroundCancellation = pipeline.load(request) { [weak self] result in
            guard case .success(.raster(let asset)) = result else { return }
            DispatchQueue.main.async { [weak self] in
                self?.windowControllers.forEach { $0.setBackgroundAsset(asset) }
            }
        }
    }
}

private extension CommandModifiers {
    var appKitFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.command) { result.insert(.command) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        return result
    }
}
