import Foundation

public enum QuotaSelector {
    public static func snapshot(from event: DecodedRateLimitEvent, sourceFingerprint: String) -> QuotaSnapshot? {
        guard event.limitID == "codex" else { return nil }
        guard let window = [event.primary, event.secondary]
            .compactMap({ $0 })
            .first(where: { $0.windowMinutes == 10_080 })
        else {
            return nil
        }
        guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent), window.resetsAt > 0 else { return nil }

        return .init(
            usedPercent: window.usedPercent,
            windowMinutes: window.windowMinutes,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetsAt)),
            observedAt: event.observedAt,
            sourceFingerprint: sourceFingerprint
        )
    }
}
