namespace CodexQuota.Windows;

public static class QuotaSelector
{
    private const int WeeklyWindowMinutes = 10_080;

    public static QuotaSnapshot? Snapshot(DecodedRateLimitEvent value, string sourceFingerprint)
    {
        if (value.LimitId != "codex")
        {
            return null;
        }

        var window = new[] { value.Primary, value.Secondary }
            .FirstOrDefault(candidate => candidate?.WindowMinutes == WeeklyWindowMinutes);
        if (window is null || !double.IsFinite(window.UsedPercent) ||
            window.UsedPercent is < 0 or > 100 || window.ResetsAt <= 0)
        {
            return null;
        }

        DateTimeOffset resetsAt;
        try
        {
            resetsAt = DateTimeOffset.FromUnixTimeSeconds(window.ResetsAt);
        }
        catch (ArgumentOutOfRangeException)
        {
            return null;
        }

        return new QuotaSnapshot(
            window.UsedPercent,
            window.WindowMinutes,
            resetsAt,
            value.ObservedAt,
            sourceFingerprint);
    }
}
