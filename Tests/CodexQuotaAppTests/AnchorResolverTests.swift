import CoreGraphics
import XCTest
@testable import CodexQuotaApp

final class AnchorResolverTests: XCTestCase {
    func testWebAreaContainerIsAllowedInMinimalAccessibilityShell() {
        let shellRoles = ["AXWindow", "AXGroup", "AXButton", "AXImage", "AXWebArea"]
        let hasDetailedRole = shellRoles.contains {
            AccessibilityRoleDetailClassifier.isDetailed(role: $0)
        }

        XCTAssertFalse(hasDetailedRole)
        XCTAssertEqual(
            SidebarWidthResolver.resolve(
                detectedSidebarWidth: nil,
                visitedElementCount: 14,
                hasDetailedWebAccessibility: hasDetailedRole,
                windowWidth: 1_501
            ),
            244
        )
    }

    func testContentRolesStillMarkAccessibilityTreeAsDetailed() {
        XCTAssertTrue(AccessibilityRoleDetailClassifier.isDetailed(role: "AXStaticText"))
        XCTAssertTrue(AccessibilityRoleDetailClassifier.isDetailed(role: "AXList"))
    }

    func testDetectedSidebarTakesPriorityOverAccessibilityTreeDetail() {
        XCTAssertEqual(
            SidebarWidthResolver.resolve(
                detectedSidebarWidth: 232,
                visitedElementCount: 100,
                hasDetailedWebAccessibility: true,
                windowWidth: 1_200
            ),
            232
        )
    }

    func testDetailedAccessibilityTreeWithoutSidebarIsTreatedAsCollapsed() {
        XCTAssertNil(SidebarWidthResolver.resolve(
            detectedSidebarWidth: nil,
            visitedElementCount: 100,
            hasDetailedWebAccessibility: true,
            windowWidth: 1_200
        ))
    }

    func testMinimalAccessibilityTreeUsesConservativeSidebarFallback() {
        XCTAssertEqual(
            SidebarWidthResolver.resolve(
                detectedSidebarWidth: nil,
                visitedElementCount: 12,
                hasDetailedWebAccessibility: false,
                windowWidth: 1_200
            ),
            244
        )
        XCTAssertEqual(
            SidebarWidthResolver.resolve(
                detectedSidebarWidth: nil,
                visitedElementCount: SidebarWidthResolver.maximumMinimalTreeElementCount,
                hasDetailedWebAccessibility: false,
                windowWidth: 1_200
            ),
            244
        )
        XCTAssertNil(SidebarWidthResolver.resolve(
            detectedSidebarWidth: nil,
            visitedElementCount: SidebarWidthResolver.maximumMinimalTreeElementCount + 1,
            hasDetailedWebAccessibility: false,
            windowWidth: 1_200
        ))
    }

    func testMinimalTreeFallbackNeverExceedsWindowAndRejectsUnsafeWidth() {
        XCTAssertEqual(
            SidebarWidthResolver.resolve(
                detectedSidebarWidth: nil,
                visitedElementCount: 12,
                hasDetailedWebAccessibility: false,
                windowWidth: 230
            ),
            230
        )
        XCTAssertNil(SidebarWidthResolver.resolve(
            detectedSidebarWidth: nil,
            visitedElementCount: 12,
            hasDetailedWebAccessibility: false,
            windowWidth: 209
        ))
    }

    func testFallbackSidebarProducesFullAnchorWidth() throws {
        let fallbackSidebarWidth = try XCTUnwrap(SidebarWidthResolver.resolve(
            detectedSidebarWidth: nil,
            visitedElementCount: 12,
            hasDetailedWebAccessibility: false,
            windowWidth: 1_200
        ))
        let anchor = try XCTUnwrap(AnchorResolver.resolve(
            snapshot: CodexWindowSnapshot(
                frame: CGRect(x: 100, y: 100, width: 1_200, height: 800),
                avatarFrame: nil,
                sidebarWidth: fallbackSidebarWidth,
                isFrontmost: true,
                isMinimized: false
            ),
            settings: .defaults
        ))

        XCTAssertEqual(anchor.origin, CGPoint(x: 154, y: 114))
        XCTAssertEqual(anchor.maximumWidth, 180)
    }

    func testSafePlacementAndHiddenStates() {
        let value = CodexWindowSnapshot(
            frame: CGRect(x: 100, y: 100, width: 1_200, height: 800),
            avatarFrame: CGRect(x: 116, y: 116, width: 30, height: 30),
            sidebarWidth: 244,
            isFrontmost: true,
            isMinimized: false
        )

        XCTAssertEqual(AnchorResolver.resolve(snapshot: value, settings: .defaults)?.origin.x, 154)
        XCTAssertNil(AnchorResolver.resolve(
            snapshot: .init(
                frame: value.frame,
                avatarFrame: value.avatarFrame,
                sidebarWidth: 244,
                isFrontmost: false,
                isMinimized: false
            ),
            settings: .defaults
        ))
        XCTAssertNil(AnchorResolver.resolve(
            snapshot: .init(
                frame: value.frame,
                avatarFrame: value.avatarFrame,
                sidebarWidth: 244,
                isFrontmost: true,
                isMinimized: true
            ),
            settings: .defaults
        ))
        XCTAssertNil(AnchorResolver.resolve(
            snapshot: .init(
                frame: value.frame,
                avatarFrame: value.avatarFrame,
                sidebarWidth: 48,
                isFrontmost: true,
                isMinimized: false
            ),
            settings: .defaults
        ))
    }

    func testPrimaryScreenAXRectConvertsToAppKitCoordinates() {
        let converted = ScreenCoordinateConverter.appKitRect(
            axRect: CGRect(x: 100, y: 200, width: 1_200, height: 800),
            screens: [CGRect(x: 0, y: 0, width: 1_920, height: 1_080)]
        )

        XCTAssertEqual(converted, CGRect(x: 100, y: 80, width: 1_200, height: 800))
    }

    func testMultipleScreensChooseLargestAXSpaceIntersection() {
        let primary = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let secondary = CGRect(x: 1_920, y: 180, width: 1_280, height: 720)
        let axRect = CGRect(x: 1_850, y: 250, width: 500, height: 300)

        let selected = ScreenCoordinateConverter.screenWithLargestIntersection(
            axRect: axRect,
            screens: [primary, secondary]
        )

        XCTAssertEqual(selected, secondary)
        XCTAssertEqual(
            ScreenCoordinateConverter.appKitRect(axRect: axRect, screens: [primary, secondary]),
            CGRect(x: 1_850, y: 530, width: 500, height: 300)
        )
    }

    func testRectOutsideAllScreensCannotBeConverted() {
        XCTAssertNil(ScreenCoordinateConverter.appKitRect(
            axRect: CGRect(x: 4_000, y: 200, width: 500, height: 300),
            screens: [CGRect(x: 0, y: 0, width: 1_920, height: 1_080)]
        ))
    }

    func testRefreshGateCoalescesRequestsAndRejectsWorkQueuedBeforeStop() throws {
        var gate = RefreshGate()
        gate.start()

        let firstTicket = try XCTUnwrap(gate.request())
        XCTAssertNil(gate.request())

        gate.stop()
        XCTAssertFalse(gate.consume(firstTicket))
        XCTAssertNil(gate.request())

        gate.start()
        let restartedTicket = try XCTUnwrap(gate.request())
        XCTAssertNotEqual(restartedTicket, firstTicket)
        XCTAssertTrue(gate.consume(restartedTicket))
        XCTAssertNotNil(gate.request())
    }

}
