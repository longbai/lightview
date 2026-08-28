import Foundation

public protocol SystemWorkspaceServing: AnyObject {
    func reveal(_ urls: [URL])
    func open(_ urls: [URL], withApplicationAt applicationURL: URL)
}

public final class SystemIntegration {
    private let workspace: any SystemWorkspaceServing

    public init(workspace: any SystemWorkspaceServing) {
        self.workspace = workspace
    }

    public func revealInFinder(_ url: URL) {
        workspace.reveal([url.standardizedFileURL])
    }

    public func openWith(_ url: URL, applicationURL: URL) {
        workspace.open(
            [url.standardizedFileURL],
            withApplicationAt: applicationURL.standardizedFileURL
        )
    }
}
