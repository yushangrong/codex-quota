import AppKit
import CodexQuotaCore
import Foundation

@MainActor
final class PollingDriver {
    typealias ScanProvider = @Sendable () async throws -> QuotaSnapshot?
    typealias CacheSaver = @MainActor (QuotaSnapshot) throws -> Void
    typealias SnapshotHandler = @MainActor (QuotaSnapshot) -> Void
    typealias SuccessHandler = @MainActor () -> Void
    typealias FailureHandler = @MainActor (DiagnosticSubsystem, DiagnosticErrorCode) -> Void

    private enum ScanOutcome: Sendable {
        case success(QuotaSnapshot?)
        case failure
    }

    private let scanProvider: ScanProvider
    private let cacheSaver: CacheSaver
    private let snapshotHandler: SnapshotHandler
    private let successHandler: SuccessHandler
    private let failureHandler: FailureHandler

    private var pollingState = PollingState()
    private var pollingTask: Task<Void, Never>?

    init(
        scanProvider: @escaping ScanProvider,
        cacheSaver: @escaping CacheSaver,
        snapshotHandler: @escaping SnapshotHandler,
        successHandler: @escaping SuccessHandler,
        failureHandler: @escaping FailureHandler
    ) {
        self.scanProvider = scanProvider
        self.cacheSaver = cacheSaver
        self.snapshotHandler = snapshotHandler
        self.successHandler = successHandler
        self.failureHandler = failureHandler
    }

    func start() {
        guard pollingTask == nil else { return }

        let runID = pollingState.start()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.pollingState.isCurrent(runID) == true,
                      let provider = self?.scanProvider else {
                    return
                }

                let outcome = await Self.scan(using: provider)
                guard !Task.isCancelled,
                      let delay = self?.commit(outcome, runID: runID) else {
                    return
                }

                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        pollingState.stop()
        pollingTask?.cancel()
        pollingTask = nil
    }

    private nonisolated static func scan(using provider: ScanProvider) async -> ScanOutcome {
        do {
            return .success(try await provider())
        } catch {
            return .failure
        }
    }

    private func commit(_ outcome: ScanOutcome, runID: UInt64) -> Int? {
        guard canCommit(runID) else { return nil }

        switch outcome {
        case .failure:
            return recordFailure(
                runID: runID,
                subsystem: .reader,
                code: .scanFailed
            )
        case let .success(scannedSnapshot):
            if let scannedSnapshot {
                do {
                    try cacheSaver(scannedSnapshot)
                } catch {
                    return recordFailure(
                        runID: runID,
                        subsystem: .cache,
                        code: .cacheSaveFailed
                    )
                }

                guard canCommit(runID) else { return nil }
                snapshotHandler(scannedSnapshot)
            }

            guard canCommit(runID),
                  let delay = pollingState.recordSuccess(for: runID) else {
                return nil
            }
            successHandler()
            return delay
        }
    }

    private func recordFailure(
        runID: UInt64,
        subsystem: DiagnosticSubsystem,
        code: DiagnosticErrorCode
    ) -> Int? {
        guard canCommit(runID),
              let delay = pollingState.recordFailure(for: runID) else {
            return nil
        }
        failureHandler(subsystem, code)
        return delay
    }

    private func canCommit(_ runID: UInt64) -> Bool {
        !Task.isCancelled && pollingState.isCurrent(runID)
    }
}

@MainActor
final class AppCoordinator {
    typealias ScanProvider = PollingDriver.ScanProvider
    typealias CacheSaver = PollingDriver.CacheSaver

    private let settings: AppSettings
    private let permissionController: PermissionController
    private let onboardingController: OnboardingController
    private let loginItemController: LoginItemController
    private let reader: QuotaEventReader
    private let cache: QuotaCache
    private let diagnosticLogger: DiagnosticLogger
    private let scanProvider: ScanProvider
    private let cacheSaver: CacheSaver

    private let windowTracker: CodexWindowTracker
    private let overlayPanel: OverlayPanelController
    private lazy var menuBar = MenuBarController(actions: makeMenuActions())
    private lazy var positionAdjustment = PositionAdjustmentController(
        adjust: { [weak self] horizontal, vertical in
            self?.adjustPosition(horizontal: horizontal, vertical: vertical)
        },
        reset: { [weak self] in
            self?.settings.resetPosition()
            self?.render()
        },
        offsets: { [weak self] in
            (
                horizontal: self?.settings.horizontalOffset ?? 0,
                vertical: self?.settings.verticalOffset ?? 0
            )
        }
    )
    private lazy var pollingDriver = PollingDriver(
        scanProvider: scanProvider,
        cacheSaver: cacheSaver,
        snapshotHandler: { [weak self] snapshot in
            self?.quotaSnapshot = snapshot
        },
        successHandler: { [weak self] in
            self?.diagnosticCode = nil
            self?.refreshDisplay()
        },
        failureHandler: { [weak self] subsystem, code in
            self?.handlePollingFailure(subsystem: subsystem, code: code)
        }
    )

    private var isStarted = false
    private var windowSnapshot: CodexWindowSnapshot?
    private var quotaSnapshot: QuotaSnapshot?
    private var display: QuotaDisplayState = .waiting
    private var diagnosticCode: DiagnosticErrorCode?

    init(
        reader: QuotaEventReader,
        cache: QuotaCache,
        diagnosticLogger: DiagnosticLogger,
        settings: AppSettings = AppSettings(),
        permissionController: PermissionController = PermissionController(),
        loginItemController: LoginItemController = LoginItemController(),
        windowTracker: CodexWindowTracker = CodexWindowTracker(),
        overlayPanel: OverlayPanelController = OverlayPanelController(),
        scanProvider: ScanProvider? = nil,
        cacheSaver: CacheSaver? = nil
    ) {
        self.reader = reader
        self.cache = cache
        self.diagnosticLogger = diagnosticLogger
        self.settings = settings
        self.permissionController = permissionController
        self.loginItemController = loginItemController
        self.windowTracker = windowTracker
        self.overlayPanel = overlayPanel
        self.onboardingController = OnboardingController(
            settings: settings,
            permissionController: permissionController
        )
        self.scanProvider = scanProvider ?? { try await reader.scan() }
        self.cacheSaver = cacheSaver ?? { try cache.save($0) }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        loadCachedSnapshot()
        _ = menuBar
        overlayPanel.setAppearance(settings.appearance)
        windowTracker.onChange = { [weak self] snapshot in
            self?.windowSnapshot = snapshot
            self?.render()
        }
        windowTracker.start()
        render()
        pollingDriver.start()
        onboardingController.presentIfNeeded()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        pollingDriver.stop()
        windowTracker.onChange = nil
        windowTracker.stop()
        positionAdjustment.dismiss()
        overlayPanel.render(state: display, anchor: nil)
    }

    private func loadCachedSnapshot() {
        do {
            quotaSnapshot = try cache.load()
            refreshDisplay()
        } catch {
            diagnosticCode = .cacheLoadFailed
            Task { await diagnosticLogger.log(subsystem: .cache, code: .cacheLoadFailed) }
        }
    }

    private func handlePollingFailure(
        subsystem: DiagnosticSubsystem,
        code: DiagnosticErrorCode
    ) {
        diagnosticCode = code
        let logger = diagnosticLogger
        Task { await logger.log(subsystem: subsystem, code: code) }
        render()
    }

    private func refreshDisplay() {
        display = quotaSnapshot.map { QuotaFormatter.display(snapshot: $0) } ?? .waiting
        render()
    }

    private func render() {
        let anchor: OverlayAnchor?
        if permissionController.isTrusted, let windowSnapshot {
            anchor = AnchorResolver.resolve(snapshot: windowSnapshot, settings: settings.snapshot)
        } else {
            anchor = nil
        }

        overlayPanel.setAppearance(settings.appearance)
        overlayPanel.render(state: display, anchor: anchor)
        menuBar.update(
            display: display,
            diagnosticCode: diagnosticCode,
            overlayEnabled: settings.overlayEnabled,
            loginEnabled: loginItemController.isEnabled,
            appearance: settings.appearance
        )
    }

    private func makeMenuActions() -> MenuBarActions {
        MenuBarActions(
            refreshState: { [weak self] in self?.render() },
            toggleOverlay: { [weak self] in
                guard let self else { return }
                self.settings.overlayEnabled.toggle()
                self.render()
            },
            toggleLoginItem: { [weak self] in self?.toggleLoginItem() },
            showPositionAdjustment: { [weak self] in self?.positionAdjustment.present() },
            selectAppearance: { [weak self] appearance in
                self?.settings.appearance = appearance
                self?.render()
            },
            openAccessibilitySettings: { [weak self] in
                self?.permissionController.openSettings()
            },
            showAbout: { [weak self] in self?.menuBar.presentAbout() },
            quit: { NSApplication.shared.terminate(nil) }
        )
    }

    private func adjustPosition(horizontal: Double, vertical: Double) {
        settings.horizontalOffset += horizontal
        settings.verticalOffset += vertical
        render()
    }

    private func toggleLoginItem() {
        do {
            try loginItemController.setEnabled(!loginItemController.isEnabled)
            diagnosticCode = nil
        } catch {
            diagnosticCode = .loginItemUpdateFailed
            Task {
                await diagnosticLogger.log(
                    subsystem: .loginItem,
                    code: .loginItemUpdateFailed
                )
            }
        }
        render()
    }
}
