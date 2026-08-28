import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        if let path = UserDefaults.standard.string(forKey: "LightViewUITestOpenPath") {
            coordinator.open(URL(fileURLWithPath: path))
        } else {
            coordinator.openEmptyWindow()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { coordinator?.open($0) }
    }
}
