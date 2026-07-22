import AppKit
import ApplicationServices

private final class CodexWindowObserverContext: @unchecked Sendable {
    weak var tracker: CodexWindowTracker?

    init(tracker: CodexWindowTracker) {
        self.tracker = tracker
    }
}

private func codexWindowObserverCallback(
    _: AXObserver,
    _: AXUIElement,
    _: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let context = Unmanaged<CodexWindowObserverContext>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        context.tracker?.handleAccessibilityChange()
    }
}

struct RefreshGate: Sendable {
    private(set) var isRunning = false
    private var generation: UInt64 = 0
    private var isPending = false

    mutating func start() {
        guard !isRunning else { return }
        generation &+= 1
        isRunning = true
        isPending = false
    }

    mutating func stop() {
        generation &+= 1
        isRunning = false
        isPending = false
    }

    mutating func request() -> UInt64? {
        guard isRunning, !isPending else { return nil }
        isPending = true
        return generation
    }

    mutating func consume(_ ticket: UInt64) -> Bool {
        guard isRunning, isPending, ticket == generation else { return false }
        isPending = false
        return true
    }
}

private struct AccessibilityLayoutInspection {
    let avatarFrame: CGRect?
    let detectedSidebarWidth: CGFloat?
    let visitedElementCount: Int
    let hasDetailedWebAccessibility: Bool
}

@MainActor
final class CodexWindowTracker {
    var onChange: ((CodexWindowSnapshot?) -> Void)?

    private static let officialBundleIdentifier = "com.openai.codex"
    private static let fallbackLocalizedName = "Codex"
    private static let maximumTraversalDepth = 8

    private var initialSampleTimer: Timer?
    private var safetySampleTimer: Timer?
    private var pendingRefreshTask: Task<Void, Never>?
    private var refreshGate = RefreshGate()
    private var observer: AXObserver?
    private var observerContext: Unmanaged<CodexWindowObserverContext>?
    private var observedApplication: AXUIElement?
    private var observedWindow: AXUIElement?
    private var observedProcessIdentifier: pid_t?
    private var hasEmitted = false
    private var lastSnapshot: CodexWindowSnapshot?

    func start() {
        guard !refreshGate.isRunning else { return }
        refreshGate.start()

        requestRefresh()
        initialSampleTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.requestRefresh()
            }
        }
        safetySampleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestRefresh()
            }
        }
    }

    func stop() {
        refreshGate.stop()
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        initialSampleTimer?.invalidate()
        initialSampleTimer = nil
        safetySampleTimer?.invalidate()
        safetySampleTimer = nil
        removeAccessibilityObserver()
        emit(nil)
    }

    fileprivate func handleAccessibilityChange() {
        requestRefresh()
    }

    private func requestRefresh() {
        guard let ticket = refreshGate.request() else { return }
        pendingRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  self.refreshGate.consume(ticket) else {
                return
            }
            self.pendingRefreshTask = nil
            self.sample()
        }
    }

    private func sample() {
        guard refreshGate.isRunning else { return }
        guard let application = frontmostCodexApplication() else {
            removeAccessibilityObserver()
            emit(nil)
            return
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        if let observedProcessIdentifier,
           observedProcessIdentifier != application.processIdentifier {
            removeAccessibilityObserver()
        }
        guard let window = focusedWindow(of: applicationElement) else {
            removeAccessibilityObserver()
            emit(nil)
            return
        }
        installAccessibilityObserver(
            processIdentifier: application.processIdentifier,
            application: applicationElement,
            window: window
        )

        guard let isMinimized = booleanAttribute(kAXMinimizedAttribute, of: window),
              !isMinimized,
              let axWindowFrame = accessibilityFrame(of: window) else {
            emit(nil)
            return
        }

        let layout = inspectLayout(of: window, windowFrame: axWindowFrame)
        guard let sidebarWidth = SidebarWidthResolver.resolve(
            detectedSidebarWidth: layout.detectedSidebarWidth,
            visitedElementCount: layout.visitedElementCount,
            hasDetailedWebAccessibility: layout.hasDetailedWebAccessibility,
            windowWidth: axWindowFrame.width
        ) else {
            emit(nil)
            return
        }

        let screens = NSScreen.screens.map(\.frame)
        guard let appKitWindowFrame = ScreenCoordinateConverter.appKitRect(
            axRect: axWindowFrame,
            screens: screens
        ) else {
            emit(nil)
            return
        }

        let appKitAvatarFrame: CGRect?
        if let axAvatarFrame = layout.avatarFrame {
            guard let convertedAvatarFrame = ScreenCoordinateConverter.appKitRect(
                axRect: axAvatarFrame,
                screens: screens
            ) else {
                emit(nil)
                return
            }
            appKitAvatarFrame = convertedAvatarFrame
        } else {
            appKitAvatarFrame = nil
        }

        emit(CodexWindowSnapshot(
            frame: appKitWindowFrame,
            avatarFrame: appKitAvatarFrame,
            sidebarWidth: sidebarWidth,
            isFrontmost: true,
            isMinimized: false
        ))
    }

    private func frontmostCodexApplication() -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        if application.bundleIdentifier == Self.officialBundleIdentifier {
            return application
        }

        let bundleIdentifier = application.bundleIdentifier ?? ""
        guard bundleIdentifier.isEmpty,
              application.localizedName == Self.fallbackLocalizedName else {
            return nil
        }
        return application
    }

    private func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        guard let value = attribute(kAXFocusedWindowAttribute, of: application),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(kAXPositionAttribute, of: element),
              let sizeValue = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        let position = unsafeDowncast(positionValue, to: AXValue.self)
        let size = unsafeDowncast(sizeValue, to: AXValue.self)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point),
              AXValueGetValue(size, .cgSize, &dimensions) else {
            return nil
        }
        return CGRect(origin: point, size: dimensions)
    }

    private func inspectLayout(
        of window: AXUIElement,
        windowFrame: CGRect
    ) -> AccessibilityLayoutInspection {
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var index = 0
        var avatarFrame: CGRect?
        var sidebarWidth: CGFloat?
        var foundDetailedRole = false

        while index < queue.count, index < 1_000 {
            let current = queue[index]
            index += 1

            let role = stringAttribute(kAXRoleAttribute, of: current.element)
            let title = stringAttribute(kAXTitleAttribute, of: current.element)
            let description = stringAttribute(kAXDescriptionAttribute, of: current.element)
            let frame = accessibilityFrame(of: current.element)

            if AccessibilityRoleDetailClassifier.isDetailed(role: role) {
                foundDetailedRole = true
            }

            if current.depth > 0, let frame {
                if isSidebarFrame(frame, within: windowFrame) {
                    let width = frame.width
                    if sidebarWidth == nil || width > sidebarWidth! {
                        sidebarWidth = width
                    }
                }

                if avatarFrame == nil,
                   isAvatarCandidate(role: role, title: title, description: description, frame: frame) {
                    avatarFrame = frame
                }
            }

            if current.depth < Self.maximumTraversalDepth {
                for child in children(of: current.element) {
                    queue.append((child, current.depth + 1))
                }
            }
        }

        return AccessibilityLayoutInspection(
            avatarFrame: avatarFrame,
            detectedSidebarWidth: sidebarWidth,
            visitedElementCount: index,
            hasDetailedWebAccessibility: foundDetailedRole
                || index > SidebarWidthResolver.maximumMinimalTreeElementCount
        )
    }

    private func isSidebarFrame(_ frame: CGRect, within windowFrame: CGRect) -> Bool {
        guard frame.width >= 32,
              frame.width <= 400,
              frame.height >= windowFrame.height * 0.65,
              abs(frame.minX - windowFrame.minX) <= 8 else {
            return false
        }
        return !frame.intersection(windowFrame).isNull
    }

    private func isAvatarCandidate(
        role: String?,
        title: String?,
        description: String?,
        frame: CGRect
    ) -> Bool {
        guard role == kAXButtonRole || role == kAXImageRole,
              frame.width >= 16,
              frame.width <= 96,
              frame.height >= 16,
              frame.height <= 96 else {
            return false
        }

        let label = [title, description]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return ["account", "avatar", "profile", "user"].contains { label.contains($0) }
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = attribute(kAXChildrenAttribute, of: element) else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        attribute(name, of: element) as? String
    }

    private func booleanAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func installAccessibilityObserver(
        processIdentifier: pid_t,
        application: AXUIElement,
        window: AXUIElement
    ) {
        if observedProcessIdentifier == processIdentifier,
           let observedWindow,
           CFEqual(observedWindow, window) {
            return
        }

        removeAccessibilityObserver()

        var newObserver: AXObserver?
        guard AXObserverCreate(processIdentifier, codexWindowObserverCallback, &newObserver) == .success,
              let newObserver else {
            return
        }

        let context = Unmanaged.passRetained(CodexWindowObserverContext(tracker: self))
        let refcon = context.toOpaque()
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)

        AXObserverAddNotification(newObserver, application, kAXFocusedWindowChangedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, window, kAXMovedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, window, kAXResizedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, window, kAXWindowMiniaturizedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, window, kAXWindowDeminiaturizedNotification as CFString, refcon)
        AXObserverAddNotification(newObserver, window, kAXUIElementDestroyedNotification as CFString, refcon)

        observer = newObserver
        observerContext = context
        observedApplication = application
        observedWindow = window
        observedProcessIdentifier = processIdentifier
    }

    private func removeAccessibilityObserver() {
        if let observer {
            if let observedApplication {
                AXObserverRemoveNotification(
                    observer,
                    observedApplication,
                    kAXFocusedWindowChangedNotification as CFString
                )
            }
            if let observedWindow {
                for notification in [
                    kAXMovedNotification,
                    kAXResizedNotification,
                    kAXWindowMiniaturizedNotification,
                    kAXWindowDeminiaturizedNotification,
                    kAXUIElementDestroyedNotification,
                ] {
                    AXObserverRemoveNotification(observer, observedWindow, notification as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        self.observer = nil
        observedApplication = nil
        observedWindow = nil
        observedProcessIdentifier = nil
        observerContext?.release()
        observerContext = nil
    }

    private func emit(_ snapshot: CodexWindowSnapshot?) {
        guard !hasEmitted || lastSnapshot != snapshot else { return }
        hasEmitted = true
        lastSnapshot = snapshot
        onChange?(snapshot)
    }
}
