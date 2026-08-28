import AppKit
import LightViewCore

final class AppKitSystemWorkspace: SystemWorkspaceServing {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func reveal(_ urls: [URL]) {
        workspace.activateFileViewerSelecting(urls)
    }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        workspace.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }
}
