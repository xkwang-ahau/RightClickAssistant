import AppKit
import FinderSync
import Observation

@MainActor
@Observable
final class FinderIntegration {
    private(set) var isEnabled = false

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }

    func showManagement() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}
