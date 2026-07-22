import CoreGraphics
import SwiftUI
import XCTest
import CodexQuotaCore
@testable import CodexQuotaApp

@MainActor
final class OverlayPresentationTests: XCTestCase {
    func testPaletteSemanticNamesMatchQuotaLevels() {
        XCTAssertEqual(QuotaPillPalette.for(level: .normal).semanticName, .green)
        XCTAssertEqual(QuotaPillPalette.for(level: .warning).semanticName, .amber)
        XCTAssertEqual(QuotaPillPalette.for(level: .critical).semanticName, .red)
        XCTAssertEqual(QuotaPillPalette.for(level: .unavailable).semanticName, .neutral)
    }

    func testSelectsLongestVariantThatFitsMeasuredWidths() {
        let expected: [(CGFloat, OverlayTextVariant)] = [
            (74, .minimal),
            (90, .compact),
            (130, .compact),
            (150, .compact),
            (167, .full),
            (180, .full),
        ]

        for (maximumWidth, variant) in expected {
            let layout = OverlayLayout.fitting(
                state: state,
                maximumWidth: maximumWidth,
                measure: measuredWidth
            )

            XCTAssertEqual(layout.presentation.variant, variant, "maximumWidth=\(maximumWidth)")
            XCTAssertLessThanOrEqual(layout.width, maximumWidth, "maximumWidth=\(maximumWidth)")
        }
    }

    func testVariantsExposeFullCompactAndMinimalCopy() {
        XCTAssertEqual(OverlayPresentation(state: state, variant: .full).visibleText, "Codex 63% · 3天后重置")
        XCTAssertEqual(OverlayPresentation(state: state, variant: .compact).visibleText, "63% · 3天")
        XCTAssertEqual(OverlayPresentation(state: state, variant: .minimal).visibleText, "63%")
        XCTAssertEqual(
            OverlayPresentation(state: .waiting, variant: .minimal).visibleText,
            "--"
        )
    }

    func testRealHostingViewFitsChosenWidthWithoutTruncatingVariant() {
        for maximumWidth in [CGFloat(74), 90, 130, 150, 167, 180] {
            let layout = OverlayLayout.fitting(
                state: state,
                maximumWidth: maximumWidth,
                measure: naturalWidth
            )
            let host = NSHostingView(
                rootView: QuotaPillView(presentation: layout.presentation)
                    .frame(width: layout.width)
            )

            XCTAssertLessThanOrEqual(host.fittingSize.width, maximumWidth, "maximumWidth=\(maximumWidth)")
        }
    }

    private let state = QuotaDisplayState(
        remainingPercent: 63,
        level: .normal,
        pillText: "Codex 63% · 3天后重置",
        compactText: "63% · 3天",
        tooltipText: "已用 37%",
        isStale: false
    )

    private func measuredWidth(_ presentation: OverlayPresentation) -> CGFloat {
        switch presentation.variant {
        case .full: 167
        case .compact: 93
        case .minimal: 60
        }
    }

    private func naturalWidth(_ presentation: OverlayPresentation) -> CGFloat {
        NSHostingView(
            rootView: QuotaPillView(presentation: presentation)
        )
        .fittingSize.width
    }
}
