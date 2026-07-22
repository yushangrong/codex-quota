import CodexQuotaCore
import Foundation
import XCTest
@testable import CodexQuotaApp

private actor SuspendedScanProvider {
    private var nextCall = 0
    private var continuations: [Int: CheckedContinuation<QuotaSnapshot?, Never>] = [:]

    func scan() async -> QuotaSnapshot? {
        await withCheckedContinuation { continuation in
            continuations[nextCall] = continuation
            nextCall += 1
        }
    }

    func waitUntilStarted(_ count: Int) async {
        while nextCall < count {
            await Task.yield()
        }
    }

    func resume(call: Int, returning snapshot: QuotaSnapshot?) {
        continuations.removeValue(forKey: call)?.resume(returning: snapshot)
    }
}

@MainActor
private final class PollingCommitRecorder {
    var cachedSnapshots: [QuotaSnapshot] = []
    var committedSnapshots: [QuotaSnapshot] = []
    var displayUpdates = 0
    var diagnostics: [DiagnosticErrorCode] = []
}

@MainActor
final class PollingDriverTests: XCTestCase {
    func testStoppedRunCannotCommitAfterRestart() async throws {
        let provider = SuspendedScanProvider()
        let recorder = PollingCommitRecorder()
        let driver = PollingDriver(
            scanProvider: { await provider.scan() },
            cacheSaver: { recorder.cachedSnapshots.append($0) },
            snapshotHandler: { recorder.committedSnapshots.append($0) },
            successHandler: { recorder.displayUpdates += 1 },
            failureHandler: { _, code in recorder.diagnostics.append(code) }
        )

        driver.start()
        await provider.waitUntilStarted(1)
        driver.stop()
        driver.start()
        await provider.waitUntilStarted(2)

        await provider.resume(call: 0, returning: Self.snapshot)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(recorder.cachedSnapshots.isEmpty)
        XCTAssertTrue(recorder.committedSnapshots.isEmpty)
        XCTAssertEqual(recorder.displayUpdates, 0)
        XCTAssertTrue(recorder.diagnostics.isEmpty)

        driver.stop()
        await provider.resume(call: 1, returning: nil)
    }

    func testSuspendedProviderDoesNotRetainDriver() async {
        let provider = SuspendedScanProvider()
        var driver: PollingDriver? = PollingDriver(
            scanProvider: { await provider.scan() },
            cacheSaver: { _ in },
            snapshotHandler: { _ in },
            successHandler: {},
            failureHandler: { _, _ in }
        )
        weak var weakDriver = driver

        driver?.start()
        await provider.waitUntilStarted(1)
        driver = nil

        XCTAssertNil(weakDriver)
        await provider.resume(call: 0, returning: nil)
    }

    private static let snapshot = QuotaSnapshot(
        usedPercent: 25,
        windowMinutes: 10_080,
        resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
        observedAt: Date(timeIntervalSince1970: 1_900_000_000),
        sourceFingerprint: "stale-run"
    )
}
