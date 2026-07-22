import AppKit
import CodexQuotaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
        ]
        let cacheURL = home
            .appendingPathComponent("Library/Application Support/CodexQuota", isDirectory: true)
            .appendingPathComponent("snapshot.json")
        let logURL = home
            .appendingPathComponent("Library/Logs/CodexQuota", isDirectory: true)
            .appendingPathComponent("app.log")

        let coordinator = AppCoordinator(
            reader: QuotaEventReader(roots: roots),
            cache: QuotaCache(fileURL: cacheURL),
            diagnosticLogger: DiagnosticLogger(fileURL: logURL)
        )
        self.coordinator = coordinator
        coordinator.start()
    }

    func applicationWillTerminate(_: Notification) {
        coordinator?.stop()
        coordinator = nil
    }
}
