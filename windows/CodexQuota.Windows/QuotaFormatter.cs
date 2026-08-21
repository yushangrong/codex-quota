using System.Globalization;

namespace CodexQuota.Windows;

public static class QuotaFormatter
{
    public static QuotaDisplayState Display(QuotaSnapshot snapshot, DateTimeOffset? currentTime = null)
    {
        var now = currentTime ?? DateTimeOffset.Now;
        if (snapshot.ResetsAt <= now)
        {
            return new QuotaDisplayState(
                null,
                QuotaLevel.Unavailable,
                "Codex -- · 等待刷新",
                "--",
                "窗口已到重置时间，等待新数据",
                true);
        }

        var remaining = Math.Clamp(
            (int)Math.Round(100 - snapshot.UsedPercent, MidpointRounding.AwayFromZero),
            0,
            100);
        var reset = Countdown(snapshot.ResetsAt, now);
        var stale = now - snapshot.ObservedAt > TimeSpan.FromMinutes(30);
        var used = (int)Math.Round(snapshot.UsedPercent, MidpointRounding.AwayFromZero);
        var tooltip = $"已用 {used}% · {snapshot.ResetsAt.LocalDateTime.ToString("g", CultureInfo.CurrentCulture)} 重置" +
            (stale ? " · 数据可能已过期" : string.Empty);

        return new QuotaDisplayState(
            remaining,
            Level(remaining),
            $"Codex {remaining}% · {reset}",
            $"{remaining}% · {reset.Replace("后重置", string.Empty, StringComparison.Ordinal)}",
            tooltip,
            stale);
    }

    public static QuotaLevel Level(int remainingPercent) => remainingPercent > 30
        ? QuotaLevel.Normal
        : remainingPercent >= 10 ? QuotaLevel.Warning : QuotaLevel.Critical;

    public static string Countdown(DateTimeOffset reset, DateTimeOffset now)
    {
        var seconds = Math.Max(0, (reset - now).TotalSeconds);
        if (seconds >= 172_800) return $"{(int)(seconds / 86_400)}天后重置";
        if (seconds >= 86_400) return "1天后重置";
        if (seconds >= 3_600) return $"{(int)(seconds / 3_600)}小时后重置";
        return $"{Math.Max(1, (int)(seconds / 60))}分钟后重置";
    }
}
