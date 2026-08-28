import AppKit

@MainActor
final class PositionAdjustmentController: NSObject {
    typealias AdjustAction = (_ horizontal: Double, _ vertical: Double) -> Void
    typealias OffsetProvider = () -> (horizontal: Double, vertical: Double)

    private let adjust: AdjustAction
    private let reset: () -> Void
    private let offsets: OffsetProvider
    private let offsetLabel = NSTextField(labelWithString: "")
    private lazy var panel = makePanel()
    private var hasPositionedPanel = false

    init(
        adjust: @escaping AdjustAction,
        reset: @escaping () -> Void,
        offsets: @escaping OffsetProvider
    ) {
        self.adjust = adjust
        self.reset = reset
        self.offsets = offsets
        super.init()
    }

    func present() {
        refreshOffsets()
        if !hasPositionedPanel {
            panel.center()
            hasPositionedPanel = true
        }
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 270),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "调整悬浮层位置"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let title = NSTextField(labelWithString: "连续点击方向按钮来微调")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.alignment = .center

        let hint = NSTextField(labelWithString: "可连续点击或按住，每次移动 2 pt")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center

        offsetLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        offsetLabel.textColor = .secondaryLabelColor
        offsetLabel.alignment = .center

        let up = directionButton(title: "↑", accessibilityLabel: "上移 2 pt", action: #selector(moveUp))
        let left = directionButton(title: "←", accessibilityLabel: "左移 2 pt", action: #selector(moveLeft))
        let right = directionButton(title: "→", accessibilityLabel: "右移 2 pt", action: #selector(moveRight))
        let down = directionButton(title: "↓", accessibilityLabel: "下移 2 pt", action: #selector(moveDown))
        let center = NSImageView(image: NSImage(systemSymbolName: "capsule", accessibilityDescription: "悬浮层") ?? NSImage())
        center.contentTintColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [NSView(), up, NSView()],
            [left, center, right],
            [NSView(), down, NSView()],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8

        let resetButton = actionButton(title: "恢复默认", action: #selector(resetPosition))
        let doneButton = actionButton(title: "完成", action: #selector(done))
        doneButton.keyEquivalent = "\r"
        let footer = NSStackView(views: [resetButton, doneButton])
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.distribution = .fillEqually
        footer.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let content = NSStackView(views: [title, hint, offsetLabel, grid, footer])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 8
        content.setCustomSpacing(14, after: offsetLabel)
        content.setCustomSpacing(16, after: grid)

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])
        panel.contentView = container
        return panel
    }

    private func directionButton(title: String, accessibilityLabel: String, action: Selector) -> NSButton {
        let button = actionButton(title: title, action: action)
        button.font = .systemFont(ofSize: 17, weight: .medium)
        button.isContinuous = true
        button.setAccessibilityLabel(accessibilityLabel)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 52),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }

    private func actionButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    private func refreshOffsets() {
        let current = offsets()
        offsetLabel.stringValue = "水平 \(formatted(current.horizontal)) pt  ·  垂直 \(formatted(current.vertical)) pt"
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func move(horizontal: Double, vertical: Double) {
        adjust(horizontal, vertical)
        refreshOffsets()
    }

    @objc private func moveLeft() { move(horizontal: -2, vertical: 0) }
    @objc private func moveRight() { move(horizontal: 2, vertical: 0) }
    @objc private func moveUp() { move(horizontal: 0, vertical: 2) }
    @objc private func moveDown() { move(horizontal: 0, vertical: -2) }

    @objc private func resetPosition() {
        reset()
        refreshOffsets()
    }

    @objc private func done() {
        dismiss()
    }
}
