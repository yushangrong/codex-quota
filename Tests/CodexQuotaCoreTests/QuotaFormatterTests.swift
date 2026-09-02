import XCTest
@testable import CodexQuotaCore

final class QuotaFormatterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemainingAndCopy() {
        let value = QuotaSnapshot(usedPercent: 37, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(259_200), observedAt: now, sourceFingerprint: "fixture")
        let display = QuotaFormatter.display(snapshot: value, now: now)
        XCTAssertEqual(display.remainingPercent, 63)
        XCTAssertEqual(display.level, .normal)
        XCTAssertEqual(display.pillText, "Codex 63% · 3天")
        XCTAssertEqual(display.compactText, "63% · 约3天")
    }

    func testFullCountdownIncludesHoursWhileCompactCountdownRoundsDays() {
        let value = QuotaSnapshot(
            usedPercent: 47,
            windowMinutes: 10_080,
            resetsAt: now.addingTimeInterval(4 * 86_400 + 19 * 3_600),
            observedAt: now,
            sourceFingerprint: "fixture"
        )

        let display = QuotaFormatter.display(snapshot: value, now: now)

        XCTAssertEqual(display.pillText, "Codex 53% · 4天19小时")
        XCTAssertEqual(display.compactText, "53% · 约5天")
        XCTAssertEqual(
            QuotaFormatter.compactCountdown(to: now.addingTimeInterval(4 * 86_400 + 11 * 3_600), now: now),
            "约4天"
        )
        XCTAssertEqual(
            QuotaFormatter.compactCountdown(to: now.addingTimeInterval(4 * 86_400 + 12 * 3_600), now: now),
            "约5天"
        )
    }

    func testThresholdsCountdownAndExpiredWindow() {
        XCTAssertEqual(QuotaLevel(remainingPercent: 30), .warning)
        XCTAssertEqual(QuotaLevel(remainingPercent: 10), .warning)
        XCTAssertEqual(QuotaLevel(remainingPercent: 31), .normal)
        XCTAssertEqual(QuotaLevel(remainingPercent: 9), .critical)
        XCTAssertEqual(QuotaFormatter.countdown(to: now.addingTimeInterval(21_600), now: now), "6小时后重置")
        let expired = QuotaSnapshot(usedPercent: 90, windowMinutes: 10_080, resetsAt: now, observedAt: now, sourceFingerprint: "fixture")
        XCTAssertEqual(QuotaFormatter.display(snapshot: expired, now: now).pillText, "Codex -- · 等待刷新")
    }
}
