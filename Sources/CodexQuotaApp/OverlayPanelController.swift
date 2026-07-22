import AppKit
import CodexQuotaCore
import SwiftUI

@MainActor
final class OverlayPanelController {
    private let panel: NSPanel = {
        let value = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        value.isOpaque = false
        value.backgroundColor = .clear
        value.hasShadow = false
        value.becomesKeyOnlyIfNeeded = true
        value.level = .floating
        value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return value
    }()

    func setAppearance(_ appearance: AppAppearance) {
        switch appearance {
        case .system:
            panel.appearance = nil
        case .dark:
            panel.appearance = NSAppearance(named: .darkAqua)
        case .light:
            panel.appearance = NSAppearance(named: .aqua)
        }
    }

    func render(state: QuotaDisplayState, anchor: OverlayAnchor?) {
        guard let anchor else {
            panel.orderOut(nil)
            return
        }

        let layout = OverlayLayout.fitting(state: state, maximumWidth: anchor.maximumWidth) {
            NSHostingView(rootView: QuotaPillView(presentation: $0)).fittingSize.width
        }
        let host = NSHostingView(
            rootView: QuotaPillView(presentation: layout.presentation)
                .frame(width: layout.width)
        )
        let width = min(anchor.maximumWidth, max(74, host.fittingSize.width))
        panel.contentView = host
        panel.setFrame(
            CGRect(origin: anchor.origin, size: CGSize(width: width, height: 30)),
            display: true
        )
        panel.orderFrontRegardless()
    }
}
