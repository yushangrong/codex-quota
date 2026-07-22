import Foundation

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date
    public let observedAt: Date
    public let sourceFingerprint: String

    public init(usedPercent: Double, windowMinutes: Int, resetsAt: Date, observedAt: Date, sourceFingerprint: String) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.sourceFingerprint = sourceFingerprint
    }
}

public enum QuotaLevel: String, Codable, Equatable, Sendable {
    case normal, warning, critical, unavailable

    public init(remainingPercent: Int) {
        self = remainingPercent > 30 ? .normal : (remainingPercent >= 10 ? .warning : .critical)
    }
}

public struct QuotaDisplayState: Equatable, Sendable {
    public let remainingPercent: Int?
    public let level: QuotaLevel
    public let pillText: String
    public let compactText: String
    public let tooltipText: String
    public let isStale: Bool

    public init(remainingPercent: Int?, level: QuotaLevel, pillText: String, compactText: String, tooltipText: String, isStale: Bool) {
        self.remainingPercent = remainingPercent
        self.level = level
        self.pillText = pillText
        self.compactText = compactText
        self.tooltipText = tooltipText
        self.isStale = isStale
    }

    public static let waiting = Self(
        remainingPercent: nil,
        level: .unavailable,
        pillText: "Codex -- · 等待数据",
        compactText: "--",
        tooltipText: "完成一次 Codex 请求后显示周额度",
        isStale: false
    )
}
