namespace CodexQuota.Windows;

public sealed record QuotaWindow(double UsedPercent, int WindowMinutes, long ResetsAt);

public sealed record DecodedRateLimitEvent(
    DateTimeOffset ObservedAt,
    string LimitId,
    QuotaWindow? Primary,
    QuotaWindow? Secondary);

public sealed record QuotaSnapshot(
    double UsedPercent,
    int WindowMinutes,
    DateTimeOffset ResetsAt,
    DateTimeOffset ObservedAt,
    string SourceFingerprint);

public enum QuotaLevel
{
    Normal,
    Warning,
    Critical,
    Unavailable,
}

public sealed record QuotaDisplayState(
    int? RemainingPercent,
    QuotaLevel Level,
    string PillText,
    string CompactText,
    string TooltipText,
    bool IsStale)
{
    public static QuotaDisplayState Waiting { get; } = new(
        null,
        QuotaLevel.Unavailable,
        "Codex -- · 等待数据",
        "--",
        "完成一次 Codex 请求后显示周额度",
        false);
}

public sealed class QuotaScanException : Exception
{
    public QuotaScanException() : base("No configured Codex data directory could be scanned.") { }
}
