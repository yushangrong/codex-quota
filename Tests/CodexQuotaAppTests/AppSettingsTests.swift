import Foundation
import XCTest
@testable import CodexQuotaApp

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchSnapshotDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(AppSettings(defaults: defaults).snapshot, .defaults)
    }

    func testValuesRoundTripThroughUserDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.horizontalOffset = 6
        settings.verticalOffset = -4
        settings.overlayEnabled = false
        settings.appearance = .dark

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.horizontalOffset, 6)
        XCTAssertEqual(restored.verticalOffset, -4)
        XCTAssertFalse(restored.overlayEnabled)
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(
            restored.snapshot,
            AppSettingsSnapshot(horizontalOffset: 6, verticalOffset: -4, overlayEnabled: false)
        )
    }

    func testInvalidAppearanceFallsBackToSystem() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("sepia", forKey: "appearance")

        XCTAssertEqual(AppSettings(defaults: defaults).appearance, .system)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
