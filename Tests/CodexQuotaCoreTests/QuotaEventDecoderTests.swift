import Foundation
import XCTest
@testable import CodexQuotaCore

final class QuotaEventDecoderTests: XCTestCase {
    func testPrimarySecondaryAndNonWeeklySelection() throws {
        let primary = try decodeFixture("weekly-primary")
        let secondary = try decodeFixture("weekly-secondary")
        let short = try decodeFixture("non-weekly")

        XCTAssertEqual(QuotaSelector.snapshot(from: primary, sourceFingerprint: "p")?.usedPercent, 37)
        XCTAssertEqual(QuotaSelector.snapshot(from: secondary, sourceFingerprint: "s")?.windowMinutes, 10_080)
        XCTAssertNil(QuotaSelector.snapshot(from: short, sourceFingerprint: "x"))
        XCTAssertFalse(String(describing: primary).contains("PRIVATE_TEXT_MUST_NOT_SURVIVE"))
    }

    private func decodeFixture(_ name: String) throws -> DecodedRateLimitEvent {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).jsonl")
        let line = try String(contentsOf: fixtureURL, encoding: .utf8)

        return try XCTUnwrap(QuotaEventDecoder.decode(line: line))
    }
}
