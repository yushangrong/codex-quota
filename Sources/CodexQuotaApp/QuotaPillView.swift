import AppKit
import CodexQuotaCore
import SwiftUI

enum OverlayTextVariant: Equatable {
    case full
    case compact
    case minimal
}

struct OverlayPresentation: Equatable {
    let state: QuotaDisplayState
    let variant: OverlayTextVariant

    var visibleText: String {
        switch variant {
        case .full:
            state.pillText
        case .compact:
            state.compactText
        case .minimal:
            state.remainingPercent.map { "\($0)%" } ?? "--"
        }
    }

    var minimumTextScale: CGFloat {
        variant == .compact ? 0.9 : 1
    }
}

struct OverlayLayout: Equatable {
    let presentation: OverlayPresentation
    let width: CGFloat

    private static let minimumWidth: CGFloat = 74
    private static let fixedChromeWidth: CGFloat = 34
    private static let minimumCompactTextScale: CGFloat = 0.9

    static func fitting(
        state: QuotaDisplayState,
        maximumWidth: CGFloat,
        measure: (OverlayPresentation) -> CGFloat
    ) -> Self {
        let full = OverlayPresentation(state: state, variant: .full)
        let fullWidth = measure(full)
        if fullWidth <= maximumWidth {
            return Self(presentation: full, width: clamped(fullWidth, maximumWidth: maximumWidth))
        }

        let compact = OverlayPresentation(state: state, variant: .compact)
        let compactWidth = measure(compact)
        if compactWidth <= maximumWidth {
            return Self(presentation: compact, width: clamped(compactWidth, maximumWidth: maximumWidth))
        }

        let compactScaledWidth = fixedChromeWidth
            + max(0, compactWidth - fixedChromeWidth) * minimumCompactTextScale
        if compactScaledWidth <= maximumWidth {
            return Self(presentation: compact, width: maximumWidth)
        }

        let minimal = OverlayPresentation(state: state, variant: .minimal)
        return Self(
            presentation: minimal,
            width: clamped(measure(minimal), maximumWidth: maximumWidth)
        )
    }

    private static func clamped(_ fittingWidth: CGFloat, maximumWidth: CGFloat) -> CGFloat {
        min(maximumWidth, max(min(minimumWidth, maximumWidth), fittingWidth))
    }
}

struct QuotaPillPalette {
    enum SemanticName: String, Equatable {
        case green
        case amber
        case red
        case neutral
    }

    let semanticName: SemanticName
    let foreground: Color
    let background: Color
    let border: Color

    static func `for`(level: QuotaLevel) -> Self {
        switch level {
        case .normal:
            return palette(
                name: .green,
                lightForeground: rgb(8, 122, 85),
                darkForeground: rgb(94, 233, 181),
                lightBackground: rgb(226, 247, 238),
                darkBackground: rgb(18, 59, 47),
                lightBorder: rgb(140, 211, 181, alpha: 0.62),
                darkBorder: rgb(71, 151, 120, alpha: 0.58)
            )
        case .warning:
            return palette(
                name: .amber,
                lightForeground: rgb(147, 96, 0),
                darkForeground: rgb(246, 200, 95),
                lightBackground: rgb(255, 245, 214),
                darkBackground: rgb(65, 49, 19),
                lightBorder: rgb(224, 190, 103, alpha: 0.62),
                darkBorder: rgb(159, 126, 50, alpha: 0.58)
            )
        case .critical:
            return palette(
                name: .red,
                lightForeground: rgb(179, 38, 30),
                darkForeground: rgb(255, 123, 114),
                lightBackground: rgb(255, 234, 232),
                darkBackground: rgb(67, 30, 29),
                lightBorder: rgb(226, 150, 145, alpha: 0.62),
                darkBorder: rgb(164, 76, 71, alpha: 0.58)
            )
        case .unavailable:
            return palette(
                name: .neutral,
                lightForeground: rgb(87, 96, 106),
                darkForeground: rgb(174, 184, 194),
                lightBackground: rgb(239, 241, 243),
                darkBackground: rgb(45, 49, 54),
                lightBorder: rgb(188, 194, 200, alpha: 0.62),
                darkBorder: rgb(99, 107, 116, alpha: 0.58)
            )
        }
    }

    private static func palette(
        name: SemanticName,
        lightForeground: NSColor,
        darkForeground: NSColor,
        lightBackground: NSColor,
        darkBackground: NSColor,
        lightBorder: NSColor,
        darkBorder: NSColor
    ) -> Self {
        Self(
            semanticName: name,
            foreground: adaptive(light: lightForeground, dark: darkForeground),
            background: adaptive(light: lightBackground, dark: darkBackground),
            border: adaptive(light: lightBorder, dark: darkBorder)
        )
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    private static func rgb(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        alpha: CGFloat = 1
    ) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }
}

struct QuotaPillView: View {
    let presentation: OverlayPresentation

    var body: some View {
        let palette = QuotaPillPalette.for(level: presentation.state.level)

        HStack(spacing: 6) {
            Circle()
                .fill(palette.foreground)
                .frame(width: 6, height: 6)
                .shadow(color: palette.foreground.opacity(0.6), radius: 4)

            Text(presentation.visibleText)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(presentation.minimumTextScale)
                .allowsTightening(true)
        }
        .foregroundStyle(palette.foreground)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(
            Capsule()
                .fill(palette.background)
                .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                        .padding(1)
                )
        )
        .help(presentation.state.tooltipText)
    }
}
