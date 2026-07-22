import AppKit

@MainActor
final class OnboardingController {
    private static let currentVersion = 1

    private let settings: AppSettings
    private let permissionController: PermissionController

    init(settings: AppSettings, permissionController: PermissionController) {
        self.settings = settings
        self.permissionController = permissionController
    }

    func presentIfNeeded() {
        guard settings.onboardingVersion < Self.currentVersion else { return }

        let alert = NSAlert()
        alert.messageText = "Codex Quota 需要辅助功能权限"
        alert.informativeText = "应用只从本机 Codex JSONL 文件读取 limit_id、used_percent、window_minutes、resets_at 和 timestamp 五个限额字段；不读取键盘输入、不截取屏幕、不发起网络请求。辅助功能权限仅用于定位 Codex 窗口并放置额度胶囊。"
        alert.addButton(withTitle: "继续授权")
        alert.addButton(withTitle: "暂不授权")

        settings.onboardingVersion = Self.currentVersion
        if alert.runModal() == .alertFirstButtonReturn {
            permissionController.request()
        }
    }
}
