import XCTest
@testable import CodexQuotaApp

final class RetryScheduleTests: XCTestCase {
    func testRetryBackoffCapsAndResets() {
        var retry = RetrySchedule()

        XCTAssertEqual((0..<5).map { _ in retry.recordFailure() }, [5, 10, 20, 40, 60])
        XCTAssertEqual(retry.recordFailure(), 60)
        retry.recordSuccess()
        XCTAssertEqual(retry.recordFailure(), 5)
    }

    func testPollingStateRejectsStoppedRunAndResetsAfterRestart() {
        var polling = PollingState()
        let firstRun = polling.start()

        XCTAssertEqual(polling.recordFailure(for: firstRun), 5)
        XCTAssertEqual(polling.recordFailure(for: firstRun), 10)
        polling.stop()
        XCTAssertNil(polling.recordSuccess(for: firstRun))
        XCTAssertNil(polling.recordFailure(for: firstRun))

        let restartedRun = polling.start()
        XCTAssertNotEqual(restartedRun, firstRun)
        XCTAssertEqual(polling.recordSuccess(for: restartedRun), 5)
        XCTAssertEqual(polling.recordFailure(for: restartedRun), 5)
    }
}
