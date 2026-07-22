import Foundation

public enum QuotaFormatter {
    public static func display(snapshot: QuotaSnapshot, now: Date = Date()) -> QuotaDisplayState {
        guard snapshot.resetsAt > now else {
            return .init(
                remainingPercent: nil,
                level: .unavailable,
                pillText: "Codex -- · 等待刷新",
                compactText: "--",
                tooltipText: "窗口已到重置时间，等待新数据",
                isStale: true
            )
        }

        let remaining = min(100, max(0, Int((100 - snapshot.usedPercent).rounded())))
        let reset = countdown(to: snapshot.resetsAt, now: now)
        let stale = now.timeIntervalSince(snapshot.observedAt) > 1_800
        return .init(
            remainingPercent: remaining,
            level: .init(remainingPercent: remaining),
            pillText: "Codex \(remaining)% · \(reset)",
            compactText: "\(remaining)% · \(reset.replacingOccurrences(of: "后重置", with: ""))",
            tooltipText: "已用 \(Int(snapshot.usedPercent.rounded()))% · \(snapshot.resetsAt.formatted(date: .abbreviated, time: .shortened)) 重置" + (stale ? " · 数据可能已过期" : ""),
            isStale: stale
        )
    }

    public static func countdown(to reset: Date, now: Date) -> String {
        let seconds = max(0, reset.timeIntervalSince(now))
        if seconds >= 172_800 { return "\(Int(seconds / 86_400))天后重置" }
        if seconds >= 86_400 { return "1天后重置" }
        if seconds >= 3_600 { return "\(Int(seconds / 3_600))小时后重置" }
        return "\(max(1, Int(seconds / 60)))分钟后重置"
    }
}
