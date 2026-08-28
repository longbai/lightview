import AppKit

@MainActor
final class AppCoordinator {
    private var windowControllers: [ViewerWindowController] = []

    func makeWindowController() -> ViewerWindowController {
        ViewerWindowController()
    }

    func openEmptyWindow() {
        let controller = makeWindowController()
        windowControllers.append(controller)
        controller.showWindow(nil)
    }
}

