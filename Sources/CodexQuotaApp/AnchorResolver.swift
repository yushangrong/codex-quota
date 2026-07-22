import CoreGraphics

struct AppSettingsSnapshot: Equatable, Sendable {
    var horizontalOffset: CGFloat
    var verticalOffset: CGFloat
    var overlayEnabled: Bool

    static let defaults = Self(horizontalOffset: 0, verticalOffset: 0, overlayEnabled: true)
}

struct CodexWindowSnapshot: Equatable, Sendable {
    let frame: CGRect
    let avatarFrame: CGRect?
    let sidebarWidth: CGFloat
    let isFrontmost: Bool
    let isMinimized: Bool
}

struct OverlayAnchor: Equatable, Sendable {
    let origin: CGPoint
    let maximumWidth: CGFloat
}

enum SidebarWidthResolver {
    static let minimumSafeSidebarWidth: CGFloat = 210
    static let fallbackSidebarWidth: CGFloat = 244
    static let maximumMinimalTreeElementCount = 16

    static func resolve(
        detectedSidebarWidth: CGFloat?,
        visitedElementCount: Int,
        hasDetailedWebAccessibility: Bool,
        windowWidth: CGFloat
    ) -> CGFloat? {
        guard windowWidth.isFinite, windowWidth >= minimumSafeSidebarWidth else { return nil }

        if let detectedSidebarWidth {
            let safeWidth = min(detectedSidebarWidth, windowWidth)
            return safeWidth >= minimumSafeSidebarWidth ? safeWidth : nil
        }

        guard visitedElementCount > 0,
              visitedElementCount <= maximumMinimalTreeElementCount,
              !hasDetailedWebAccessibility else {
            return nil
        }

        return min(fallbackSidebarWidth, windowWidth)
    }
}

enum AccessibilityRoleDetailClassifier {
    private static let minimalShellRoles: Set<String> = [
        "AXWindow",
        "AXGroup",
        "AXButton",
        "AXImage",
        "AXWebArea",
    ]

    static func isDetailed(role: String?) -> Bool {
        guard let role else { return false }
        return !minimalShellRoles.contains(role)
    }
}

enum AnchorResolver {
    static func resolve(snapshot: CodexWindowSnapshot, settings: AppSettingsSnapshot) -> OverlayAnchor? {
        guard settings.overlayEnabled,
              snapshot.isFrontmost,
              !snapshot.isMinimized,
              snapshot.sidebarWidth >= SidebarWidthResolver.minimumSafeSidebarWidth else {
            return nil
        }

        let avatar = snapshot.avatarFrame ?? CGRect(
            x: snapshot.frame.minX + 16,
            y: snapshot.frame.minY + 14,
            width: 30,
            height: 30
        )
        let origin = CGPoint(
            x: avatar.maxX + 8 + settings.horizontalOffset,
            y: avatar.minY + settings.verticalOffset
        )
        let availableWidth = snapshot.frame.minX + snapshot.sidebarWidth - 10 - origin.x
        guard availableWidth >= 74 else { return nil }

        return OverlayAnchor(origin: origin, maximumWidth: min(180, availableWidth))
    }
}

enum ScreenCoordinateConverter {
    static func appKitRect(axRect: CGRect, screens: [CGRect]) -> CGRect? {
        guard let primaryScreen = screens.first,
              let appKitScreen = screenWithLargestIntersection(axRect: axRect, screens: screens) else {
            return nil
        }

        let axScreen = axScreenFrame(appKitFrame: appKitScreen, primaryFrame: primaryScreen)
        let localX = axRect.minX - axScreen.minX
        let localTop = axRect.minY - axScreen.minY
        return CGRect(
            x: appKitScreen.minX + localX,
            y: appKitScreen.maxY - localTop - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    static func screenWithLargestIntersection(axRect: CGRect, screens: [CGRect]) -> CGRect? {
        guard let primaryScreen = screens.first else { return nil }

        var selectedScreen: CGRect?
        var largestArea: CGFloat = 0
        for screen in screens {
            let axScreen = axScreenFrame(appKitFrame: screen, primaryFrame: primaryScreen)
            let intersection = axRect.intersection(axScreen)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > largestArea {
                selectedScreen = screen
                largestArea = area
            }
        }
        return selectedScreen
    }

    private static func axScreenFrame(appKitFrame: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: primaryFrame.maxY - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}
