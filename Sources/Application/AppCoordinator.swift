import AppKit
import LightViewCore

@MainActor
final class AppCoordinator: NSObject {
    private let preferences = PreferencesStore()
    private let pipeline = ImageLoadPipeline()
    private var windowControllers: [ViewerWindowController] = []

    override init() {
        super.init()
        buildMainMenu()
    }

    func makeWindowController() -> ViewerWindowController {
        let controller = ViewerWindowController(
            session: ViewingSession(loader: pipeline),
            preferences: preferences,
            onOpenPanelRequest: { [weak self] in self?.showOpenPanel(nil) }
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
    }

    @objc func newWindow(_ sender: Any?) { openEmptyWindow() }

    @objc func showOpenPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    @objc func showWelcomeGuide(_ sender: Any?) {
        let controller = windowControllers.first ?? makeWindowController()
        controller.showWindow(nil)
        controller.showWelcome()
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About LightView", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LightView", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        add(.newWindow, to: fileMenu, action: #selector(newWindow(_:)), target: self)
        add(.open, to: fileMenu, action: #selector(showOpenPanel(_:)), target: self)
        fileMenu.addItem(.separator())
        add(.closeWindow, to: fileMenu, action: #selector(NSWindow.performClose(_:)))
        add(.information, to: fileMenu, action: #selector(NSResponder.showImageInformation(_:)))
        add(.revealInFinder, to: fileMenu, action: #selector(NSResponder.revealImageInFinder(_:)))
        fileMenu.addItem(.separator())
        add(.exportMP4, to: fileMenu, action: #selector(NSResponder.exportMP4(_:)))
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

@objc private extension NSResponder {
    func showImageInformation(_ sender: Any?) {}
    func revealImageInFinder(_ sender: Any?) {}
    func exportMP4(_ sender: Any?) {}
}
