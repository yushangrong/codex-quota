import AppKit
import CodexQuotaCore

@MainActor
struct MenuBarActions {
    let refreshState: () -> Void
    let toggleOverlay: () -> Void
    let toggleLoginItem: () -> Void
    let moveLeft: () -> Void
    let moveRight: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let resetPosition: () -> Void
    let selectAppearance: (AppAppearance) -> Void
    let openAccessibilitySettings: () -> Void
    let showAbout: () -> Void
    let quit: () -> Void
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let actions: MenuBarActions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let currentQuotaItem = NSMenuItem(title: "当前额度：等待数据", action: nil, keyEquivalent: "")
    private let diagnosticItem = NSMenuItem(title: "诊断：正常", action: nil, keyEquivalent: "")
    private let overlayItem = NSMenuItem(title: "显示悬浮层", action: #selector(toggleOverlay), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "开机启动", action: #selector(toggleLoginItem), keyEquivalent: "")
    private var appearanceItems: [AppAppearance: NSMenuItem] = [:]

    init(actions: MenuBarActions) {
        self.actions = actions
        super.init()

        statusItem.button?.title = "Codex --"
        statusItem.button?.toolTip = "Codex 周额度"
        currentQuotaItem.isEnabled = false
        diagnosticItem.isEnabled = false

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(currentQuotaItem)
        menu.addItem(diagnosticItem)
        menu.addItem(.separator())
        menu.addItem(configure(overlayItem, action: #selector(toggleOverlay)))
        menu.addItem(configure(loginItem, action: #selector(toggleLoginItem)))
        menu.addItem(positionMenuItem())
        menu.addItem(actionItem("恢复默认位置", action: #selector(resetPosition)))
        menu.addItem(appearanceMenuItem())
        menu.addItem(.separator())
        menu.addItem(actionItem("打开辅助功能设置", action: #selector(openAccessibilitySettings)))
        menu.addItem(actionItem("关于 Codex Quota", action: #selector(showAbout)))
        menu.addItem(actionItem("退出", action: #selector(quit)))
        statusItem.menu = menu
    }

    func update(
        display: QuotaDisplayState,
        diagnosticCode: DiagnosticErrorCode?,
        overlayEnabled: Bool,
        loginEnabled: Bool,
        appearance: AppAppearance
    ) {
        statusItem.button?.title = "Codex \(display.compactText)"
        statusItem.button?.toolTip = display.tooltipText
        currentQuotaItem.title = "当前额度：\(display.pillText)"
        diagnosticItem.title = diagnosticCode.map { "诊断：\($0.rawValue)" } ?? "诊断：正常"
        overlayItem.state = overlayEnabled ? .on : .off
        loginItem.state = loginEnabled ? .on : .off
        for (candidate, item) in appearanceItems {
            item.state = candidate == appearance ? .on : .off
        }
    }

    func presentAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.1.0"
        let alert = NSAlert()
        alert.messageText = "Codex Quota \(version)"
        alert.informativeText = "GitHub: github.com/yushangrong/codex-quota\n非 OpenAI 官方项目"
        alert.addButton(withTitle: "打开 GitHub")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "https://github.com/yushangrong/codex-quota") {
            NSWorkspace.shared.open(url)
        }
    }

    func menuWillOpen(_: NSMenu) {
        actions.refreshState()
    }

    private func positionMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "调整位置", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(actionItem("左移 2 pt", action: #selector(moveLeft)))
        submenu.addItem(actionItem("右移 2 pt", action: #selector(moveRight)))
        submenu.addItem(actionItem("上移 2 pt", action: #selector(moveUp)))
        submenu.addItem(actionItem("下移 2 pt", action: #selector(moveDown)))
        item.submenu = submenu
        return item
    }

    private func appearanceMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (appearance, title, tag) in [
            (AppAppearance.system, "跟随系统", 0),
            (.dark, "深色", 1),
            (.light, "浅色", 2),
        ] {
            let child = actionItem(title, action: #selector(selectAppearance(_:)))
            child.tag = tag
            appearanceItems[appearance] = child
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        configure(NSMenuItem(title: title, action: action, keyEquivalent: ""), action: action)
    }

    private func configure(_ item: NSMenuItem, action: Selector) -> NSMenuItem {
        item.target = self
        item.action = action
        item.isEnabled = true
        return item
    }

    @objc private func toggleOverlay() { actions.toggleOverlay() }
    @objc private func toggleLoginItem() { actions.toggleLoginItem() }
    @objc private func moveLeft() { actions.moveLeft() }
    @objc private func moveRight() { actions.moveRight() }
    @objc private func moveUp() { actions.moveUp() }
    @objc private func moveDown() { actions.moveDown() }
    @objc private func resetPosition() { actions.resetPosition() }
    @objc private func openAccessibilitySettings() { actions.openAccessibilitySettings() }
    @objc private func showAbout() { actions.showAbout() }
    @objc private func quit() { actions.quit() }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        let appearance: AppAppearance
        switch sender.tag {
        case 1: appearance = .dark
        case 2: appearance = .light
        default: appearance = .system
        }
        actions.selectAppearance(appearance)
    }
}
