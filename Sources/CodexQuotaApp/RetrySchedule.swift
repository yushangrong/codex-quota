struct RetrySchedule: Sendable {
    private var failures = 0

    mutating func recordFailure() -> Int {
        defer { failures += 1 }
        return min(60, 5 * (1 << min(failures, 4)))
    }

    mutating func recordSuccess() {
        failures = 0
    }
}

struct PollingState: Sendable {
    private var runID: UInt64 = 0
    private var isRunning = false
    private var retry = RetrySchedule()

    mutating func start() -> UInt64 {
        if !isRunning {
            runID &+= 1
            isRunning = true
            retry.recordSuccess()
        }
        return runID
    }

    mutating func stop() {
        runID &+= 1
        isRunning = false
        retry.recordSuccess()
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        isRunning && candidate == runID
    }

    mutating func recordSuccess(for candidate: UInt64) -> Int? {
        guard isCurrent(candidate) else { return nil }
        retry.recordSuccess()
        return 5
    }

    mutating func recordFailure(for candidate: UInt64) -> Int? {
        guard isCurrent(candidate) else { return nil }
        return retry.recordFailure()
    }
}
